#!/usr/bin/env bash
#
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2023 NextGen Healthcare
# SPDX-FileCopyrightText: 2025 Kaur Palang
#
# Applies the container's environment variables and secrets to the engine's
# configuration, then runs the command (./oieserver by default). Runs on every
# start, so each step must give the same result when repeated.

set -eu -o pipefail
shopt -s nullglob

APP_DIR=/opt/engine
MIRTH_PROPERTIES="$APP_DIR/conf/mirth.properties"
# Included from conf/custom.vmoptions (see Dockerfile) and rewritten on every start.
DOCKER_VMOPTIONS="$APP_DIR/conf/docker.vmoptions"

fail() {
	echo "entrypoint: $*" >&2
	exit 1
}

trim() {
	local s=$1
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

# set_property <key> <value>
# Replaces every "key = ..." line in mirth.properties, or appends one. The key
# and value reach awk through the environment, so no character in them is special.
set_property() {
	local key=$1 value=$2 tmp
	if [[ $value == *$'\n'* ]]; then
		fail "the value for ${key} contains a newline, which mirth.properties can't hold"
	fi
	tmp=$(mktemp)
	KEY="$key" VALUE="$value" awk '
		BEGIN { key = ENVIRON["KEY"]; value = ENVIRON["VALUE"] }
		{ k = $0; sub(/[ \t]*[=:].*/, "", k); sub(/^[ \t]+/, "", k) }
		k == key { print key " = " value; found = 1; next }
		{ print }
		END { if (!found) print key " = " value }
	' "$MIRTH_PROPERTIES" > "$tmp"
	# Write in place rather than mv, so a bind-mounted mirth.properties also works.
	cat "$tmp" > "$MIRTH_PROPERTIES"
	rm -f "$tmp"
}

# download <url> <file>
download() {
	local insecure=()
	if [ "${ALLOW_INSECURE:-}" = "true" ]; then
		insecure=(--insecure)
	fi
	echo "Downloading $1"
	curl "${insecure[@]}" --silent --show-error --location --fail --output "$2" "$1" \
		|| fail "download failed: $1"
}

for extension in "$APP_DIR"/custom-extensions/*.zip; do
	echo "Installing custom extension ${extension##*/}"
	unzip -o -q "$extension" -d "$APP_DIR/extensions"
done

# set storepass and keypass to 'changeme' so they aren't overwritten later
set_property keystore.storepass changeme
set_property keystore.keypass changeme

# Named variables. Each is applied when set, even to an empty value.
declare -A named_properties=(
	[DATABASE]=database
	[DATABASE_USERNAME]=database.username
	[DATABASE_PASSWORD]=database.password
	[DATABASE_URL]=database.url
	[DATABASE_MAX_CONNECTIONS]=database.max-connections
	[DATABASE_MAX_RETRY]=database.connection.maxretry
	[DATABASE_RETRY_WAIT]=database.connection.retrywaitinmilliseconds
	[KEYSTORE_STOREPASS]=keystore.storepass
	[KEYSTORE_KEYPASS]=keystore.keypass
	[KEYSTORE_TYPE]=keystore.type
	[SESSION_STORE]=server.api.sessionstore
)
for var in "${!named_properties[@]}"; do
	if [ -n "${!var+x}" ]; then
		set_property "${named_properties[$var]}" "x${!var}"
	fi
done

if [ -n "${SERVER_ID+x}" ]; then
	printf 'server.id = %s\n' "$SERVER_ID" > "$APP_DIR/appdata/server.id"
fi

# Variables starting with _MP_ become properties, skipping empty values:
# _MP_DATABASE_MAX__CONNECTIONS -> database.max-connections
for var in "${!_MP_@}"; do
	value=${!var}
	if [ -z "$(trim "$value")" ]; then
		continue
	fi
	key=${var#_MP_}
	key=${key//__/-}
	key=${key//_/.}
	set_property "${key,,}" "$value"
done

# The mirth_properties secret is a properties file merged line by line.
if [ -f /run/secrets/mirth_properties ]; then
	while IFS= read -r line || [ -n "$line" ]; do
		case $(trim "$line") in
			'' | '#'* | '!'*) continue ;;
		esac
		if [[ $line != *=* ]]; then
			continue
		fi
		key=$(trim "${line%%=*}")
		value=$(trim "${line#*=}")
		if [ -n "$key" ] && [ -n "$value" ]; then
			set_property "$key" "$value"
		fi
	done < /run/secrets/mirth_properties
fi

# JVM options: VMOPTIONS (comma separated), then the oieserver_vmoptions secret
# (or its old name, mcserver_vmoptions). The file is included last, so these win.
{
	if [ -n "${VMOPTIONS:-}" ]; then
		IFS=, read -ra vmoptions <<< "$VMOPTIONS"
		for vmoption in "${vmoptions[@]}"; do
			vmoption=$(trim "$vmoption")
			if [ -n "$vmoption" ]; then
				printf '%s\n' "$vmoption"
			fi
		done
	fi
	for secret in /run/secrets/oieserver_vmoptions /run/secrets/mcserver_vmoptions; do
		if [ -f "$secret" ]; then
			cat "$secret"
			echo
			break
		fi
	done
} > "$DOCKER_VMOPTIONS"

download_dir=$(mktemp -d)
trap 'rm -rf "$download_dir"' EXIT

if [ -n "${CUSTOM_JARS_DOWNLOAD:-}" ]; then
	download "$CUSTOM_JARS_DOWNLOAD" "$download_dir/userJars.zip"
	echo "Unzipping custom jars into $APP_DIR/server-launcher-lib"
	unzip -o -q "$download_dir/userJars.zip" -d "$APP_DIR/server-launcher-lib"
fi

if [ -n "${EXTENSIONS_DOWNLOAD:-}" ]; then
	download "$EXTENSIONS_DOWNLOAD" "$download_dir/userExtensions.zip"
	unzip -o -q "$download_dir/userExtensions.zip" -d "$download_dir/extensions"
	for extension in "$download_dir"/extensions/*.zip; do
		echo "Installing extension ${extension##*/}"
		unzip -o -q "$extension" -d "$APP_DIR/extensions"
	done
fi

if [ -n "${KEYSTORE_DOWNLOAD:-}" ]; then
	download "$KEYSTORE_DOWNLOAD" "$APP_DIR/appdata/keystore.jks"
fi

rm -rf "$download_dir"
trap - EXIT

if [ -n "${DELAY:-}" ]; then
	sleep "$DELAY"
fi

exec "$@"
