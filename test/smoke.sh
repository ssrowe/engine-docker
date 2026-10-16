#!/usr/bin/env bash
#
# Starts an image and checks that Engine works: it answers on 8443, admin/admin
# can log in, /api/server/version reports the expected version, and the server
# runs as uid 1000 with no extra groups. Containers run with all capabilities
# dropped and no-new-privileges, as the README recommends.
#
# Usage: test/smoke.sh <image> <expected-version> [derby|postgres]
#   derby     the embedded database (default)
#   postgres  PostgreSQL from test/compose.postgres.yaml

set -eu -o pipefail

image=${1:?usage: $0 <image> <expected-version> [derby|postgres]}
expected_version=${2:?usage: $0 <image> <expected-version> [derby|postgres]}
database=${3:-derby}
here=$(cd "$(dirname "$0")" && pwd)
project=smoke-$$
cookies=$(mktemp)

case $database in
	derby)
		container=$(docker run -d --name "$project" --cap-drop ALL --security-opt no-new-privileges \
			-p 127.0.0.1::8443 "$image")
		logs() { docker logs "$container" 2>&1 | tail -n 100; }
		cleanup() { docker rm -f "$container" > /dev/null; rm -f "$cookies"; }
		;;
	postgres)
		compose() { ENGINE_IMAGE=$image docker compose -f "$here/compose.postgres.yaml" -p "$project" "$@"; }
		compose --progress quiet up -d --quiet-pull
		container=$(compose ps -q engine)
		logs() { compose logs --no-color 2>&1 | tail -n 100; }
		cleanup() { compose down -v > /dev/null 2>&1; rm -f "$cookies"; }
		;;
	*)
		echo "unknown database: $database" >&2
		exit 2
		;;
esac
trap cleanup EXIT

fail() {
	echo "FAIL ($database): $*" >&2
	logs >&2
	exit 1
}

port=$(docker port "$container" 8443/tcp | head -n 1)
url="https://${port}"
api() { curl --silent --insecure --cookie "$cookies" --cookie-jar "$cookies" -H 'X-Requested-With: OpenAPI' "$@"; }

echo "Waiting for Engine at $url"
for _ in $(seq 1 150); do
	if [ "$(docker inspect -f '{{.State.Running}}' "$container")" != true ]; then
		fail "container exited"
	fi
	code=$(api -o /dev/null -w '%{http_code}' "$url/api/server/version" || true)
	if [ "$code" != 000 ]; then
		break
	fi
	sleep 2
done
[ "$code" != 000 ] || fail "no response on 8443 after 300s"

code=$(api -o /dev/null -w '%{http_code}' -d username=admin -d password=admin "$url/api/users/_login")
[ "$code" = 200 ] || fail "login returned HTTP $code"

version=$(api -H 'Accept: text/plain' "$url/api/server/version")
[ "$version" = "$expected_version" ] || fail "server version is '$version', expected '$expected_version'"

ids=$(docker exec "$container" sh -c 'echo "$(id -u) $(id -G)"')
[ "$ids" = "1000 1000" ] || fail "expected uid 1000 with only group 1000, got '$ids'"

if [ "$database" = postgres ]; then
	tables=$(compose exec -T db psql -U engine -d engine -tAc "select count(*) from information_schema.tables where table_name = 'channel'")
	[ "$tables" = 1 ] || fail "Engine didn't create its tables in PostgreSQL"
fi

echo "ok ($database): $image is Engine $version, running as uid 1000"
