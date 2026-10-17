#!/usr/bin/env bash
#
# Tests deploy/entrypoint.sh inside a built image. Most cases run the
# entrypoint with a short command in place of the server and check the files
# it wrote.
#
# Usage: test/entrypoint-test.sh <image>

set -u -o pipefail

image=${1:?usage: $0 <image>}
failures=0
work=$(mktemp -d)
containers=()
cleanup() {
	if [ ${#containers[@]} -gt 0 ]; then
		docker rm -f "${containers[@]}" > /dev/null 2>&1
	fi
	rm -rf "$work"
}
trap cleanup EXIT

pass() { echo "ok   - $1"; }
fail() {
	echo "FAIL - $1"
	if [ -n "${2:-}" ]; then
		printf '%s\n' "$2" | sed 's/^/       /'
	fi
	failures=$((failures + 1))
}

# run <docker run options...> -- <command...>
run() {
	local opts=()
	while [ "$1" != "--" ]; do
		opts+=("$1")
		shift
	done
	shift
	docker run --rm "${opts[@]}" "$image" "$@" 2>&1
}

# expect_line <name> <output> <exact line>
expect_line() {
	if grep -qxF -- "$3" <<< "$2"; then
		pass "$1"
	else
		fail "$1" "expected line: $3"
	fi
}

# count_lines <output> <regex>
count_lines() {
	grep -cE -- "$2" <<< "$1"
}

special='p&a\s/s|w#é'

out=$(run -e "DATABASE_PASSWORD=$special" -e "DATABASE_URL=jdbc:postgresql://db:5432/mirthdb?a=1&b=2" -- cat conf/mirth.properties)
expect_line "special characters in a named variable" "$out" "database.password = $special"
expect_line "URL with & and /" "$out" "database.url = jdbc:postgresql://db:5432/mirthdb?a=1&b=2"

out=$(run -e "_MP_DATABASE=postgres" -e "_MP_HTTP_PORT=8081" -e "_MP_DATABASE__READONLY_MAX__CONNECTIONS=7" \
	-e "_MP_FOO_BAR=1" -e "_MP_FOO_BAR_BAZ=2" -e "_MP_KEYSTORE_TYPE=$special" -- cat conf/mirth.properties)
expect_line "_MP_ key that prefixes other keys" "$out" "database = postgres"
expect_line "_MP_ leaves keys it prefixes alone" "$out" "database.url = jdbc:derby:\${dir.appdata}/mirthdb;create=true"
expect_line "_MP_ key with __ to -" "$out" "database-readonly.max-connections = 7"
expect_line "_MP_ http.port" "$out" "http.port = 8081"
expect_line "_MP_ leaves https.port alone" "$out" "https.port = 8443"
expect_line "_MP_ special characters" "$out" "keystore.type = $special"
if [ "$(count_lines "$out" '^foo\.bar = 1$')" = 1 ] && [ "$(count_lines "$out" '^foo\.bar\.baz = 2$')" = 1 ]; then
	pass "_MP_ new keys where one prefixes the other"
else
	fail "_MP_ new keys where one prefixes the other" "$(grep '^foo' <<< "$out")"
fi

printf 'database.username = %s\n# comment = ignored\ndatabase.password=%s\nnew.key   =   spaced  ' "$special" "$special" > "$work/mirth_properties"
chmod 644 "$work/mirth_properties"
out=$(run -v "$work/mirth_properties:/run/secrets/mirth_properties:ro" -- cat conf/mirth.properties)
expect_line "mirth_properties secret, special characters" "$out" "database.username = $special"
expect_line "mirth_properties secret, no spaces around =" "$out" "database.password = $special"
expect_line "mirth_properties secret, last line without newline" "$out" "new.key = spaced"
if grep -q '^# comment' <<< "$out"; then
	fail "mirth_properties secret skips comments"
else
	pass "mirth_properties secret skips comments"
fi

out=$(run -e "SERVER_ID=a/b&c" -- cat appdata/server.id)
expect_line "SERVER_ID" "$out" "server.id = a/b&c"

out=$(run -e "DATABASE_PASSWORD=$(printf 'a\nb')" -- true)
status=$?
if [ "$status" -ne 0 ] && grep -q 'contains a newline' <<< "$out"; then
	pass "value with a newline is rejected"
else
	fail "value with a newline is rejected" "exit $status: $out"
fi

out=$(run -e "VMOPTIONS=-Xms64m, -Dtest.a=1" -- cat conf/docker.vmoptions)
if [ "$out" = $'-Xms64m\n-Dtest.a=1' ]; then
	pass "VMOPTIONS written one per line"
else
	fail "VMOPTIONS written one per line" "$out"
fi

printf -- '-Dtest.secret=1\n' > "$work/vmoptions"
chmod 644 "$work/vmoptions"
out=$(run -v "$work/vmoptions:/run/secrets/mcserver_vmoptions:ro" -- cat conf/docker.vmoptions)
expect_line "legacy mcserver_vmoptions secret" "$out" "-Dtest.secret=1"

# The server's JVM must get -Xmx from VMOPTIONS last, after the default -Xmx256m.
name=entrypoint-test-vmoptions-$$
containers+=("$name")
docker run -d --name "$name" -e "VMOPTIONS=-Xmx300m" "$image" > /dev/null
cmdline=""
for _ in $(seq 1 60); do
	cmdline=$(docker exec "$name" cat /proc/1/cmdline 2> /dev/null | tr '\0' '\n')
	if grep -q '^-Xmx' <<< "$cmdline"; then
		break
	fi
	sleep 1
done
last_xmx=$(grep '^-Xmx' <<< "$cmdline" | tail -n 1)
if [ "$last_xmx" = "-Xmx300m" ]; then
	pass "VMOPTIONS -Xmx is the last -Xmx on the java command line"
else
	fail "VMOPTIONS -Xmx is the last -Xmx on the java command line" "$(grep '^-Xmx' <<< "$cmdline")"
fi
docker rm -f "$name" > /dev/null

name=entrypoint-test-restart-$$
containers+=("$name")
docker run -d --name "$name" -e "VMOPTIONS=-Xmx300m" -e "_MP_FOO_BAR=1" "$image" sleep infinity > /dev/null
docker restart -t 0 "$name" > /dev/null
docker restart -t 0 "$name" > /dev/null
# Wait until the entrypoint has finished and exec'd the command.
for _ in $(seq 1 30); do
	if [ "$(docker exec "$name" cat /proc/1/comm 2> /dev/null)" = sleep ]; then
		break
	fi
	sleep 1
done
vm=$(docker exec "$name" cat conf/docker.vmoptions)
props=$(docker exec "$name" cat conf/mirth.properties)
if [ "$vm" = "-Xmx300m" ] && [ "$(count_lines "$props" '^foo\.bar = ')" = 1 ] \
	&& [ "$(docker exec "$name" grep -c 'docker.vmoptions' conf/custom.vmoptions)" = 1 ]; then
	pass "restart doesn't duplicate lines"
else
	fail "restart doesn't duplicate lines" "docker.vmoptions: $vm"
fi
docker rm -f "$name" > /dev/null

mkdir -p "$work/custom-extensions"
python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1], "w").writestr("test-extension/plugin.xml", "<pluginMetaData/>")' \
	"$work/custom-extensions/test-extension.zip"
chmod -R a+rX "$work/custom-extensions"
out=$(run -v "$work/custom-extensions:/opt/engine/custom-extensions:ro" -- cat extensions/test-extension/plugin.xml)
expect_line "custom-extensions zip is unpacked" "$out" "<pluginMetaData/>"

mkdir -p "$work/certificates"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=engine-docker test CA" \
	-keyout "$work/ca.key" -out "$work/certificates/test-ca.crt" 2> /dev/null
chmod -R a+rX "$work/certificates"
out=$(run -e USE_SYSTEM_CA_CERTS=1 -v "$work/certificates:/certificates:ro" -- printenv JAVA_TOOL_OPTIONS)
if grep -q 'Using a temporary truststore' <<< "$out" && grep -q 'trustStore=' <<< "$out"; then
	pass "USE_SYSTEM_CA_CERTS uses a temporary truststore"
else
	fail "USE_SYSTEM_CA_CERTS uses a temporary truststore" "$out"
fi

for var in CUSTOM_JARS_DOWNLOAD EXTENSIONS_DOWNLOAD KEYSTORE_DOWNLOAD; do
	out=$(run -e "$var=http://127.0.0.1:9/missing.zip" -- echo started)
	status=$?
	if [ "$status" -ne 0 ] && grep -q 'download failed' <<< "$out" && ! grep -q started <<< "$out"; then
		pass "$var failure stops the container"
	else
		fail "$var failure stops the container" "exit $status: $out"
	fi
done

if [ "$failures" -ne 0 ]; then
	echo "$failures test(s) failed"
	exit 1
fi
echo "All entrypoint tests passed"
