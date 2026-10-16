#!/usr/bin/env bash
#
# Tests deploy/tags.sh against a table of cases.
#
# Usage: test/tags-test.sh

set -u -o pipefail

tags=$(cd "$(dirname "$0")/../deploy" && pwd)/tags.sh
failures=0

# check <name> <expected tags, space separated> <tags.sh arguments...>
check() {
	local name=$1 expected=$2 actual
	shift 2
	actual=$("$tags" "$@" 2>&1 | tr '\n' ' ' | sed 's/ $//')
	if [ "$actual" = "$expected" ]; then
		echo "ok   - $name"
	else
		echo "FAIL - $name"
		echo "       expected: $expected"
		echo "       actual:   $actual"
		failures=$((failures + 1))
	fi
}

# check_fails <name> <tags.sh arguments...>
check_fails() {
	local name=$1
	shift
	if "$tags" "$@" > /dev/null 2>&1; then
		echo "FAIL - $name (expected an error)"
		failures=$((failures + 1))
	else
		echo "ok   - $name"
	fi
}

check "immutable, default variant" "4.6.0-r1 4.6.0-jre21-noble-r1" immutable 4.6.0 1 jre-noble
check "immutable, jdk" "4.6.0-jdk-r2 4.6.0-jdk21-noble-r2" immutable 4.6.0 2 jdk-noble
check "immutable, alpine" "4.6.0-alpine-r10 4.6.0-jre21-alpine-r10" immutable 4.6.0 10 jre-alpine
check "immutable ignores latest flags" "4.6.0-r1 4.6.0-jre21-noble-r1" immutable 4.6.0 1 jre-noble true true
check "immutable, rc" "4.7.0-rc1-jdk-r1 4.7.0-rc1-jdk21-noble-r1" immutable 4.7.0-rc1 1 jdk-noble

check "GA latest, default variant" \
	"4.6.0 4.6.0-jre21-noble 4.6.0-ubuntu 4.6.0-ubuntu-jre 4.6 latest latest-ubuntu latest-ubuntu-jre" \
	mutable 4.6.0 1 jre-noble true true
check "GA latest, jdk" \
	"4.6.0-jdk 4.6.0-jdk21-noble 4.6.0-ubuntu-jdk 4.6-jdk latest-jdk latest-ubuntu-jdk" \
	mutable 4.6.0 1 jdk-noble true true
check "GA latest, alpine" \
	"4.6.0-alpine 4.6.0-jre21-alpine 4.6.0-alpine-jre 4.6-alpine latest-alpine latest-alpine-jre" \
	mutable 4.6.0 1 jre-alpine true true
check "older patch in an older minor" \
	"4.6.0 4.6.0-jre21-noble 4.6.0-ubuntu 4.6.0-ubuntu-jre" \
	mutable 4.6.0 3 jre-noble false false
check "highest patch of an older minor (4.6.1 while 4.7 is latest)" \
	"4.6.1-alpine 4.6.1-jre21-alpine 4.6.1-alpine-jre 4.6-alpine" \
	mutable 4.6.1 1 jre-alpine false true
check "rc, highest pre-release" "4.7.0-rc1 4.7.0-rc1-jre21-noble rc" mutable 4.7.0-rc1 1 jre-noble true
check "rc, alpine" "4.7.0-rc2-alpine 4.7.0-rc2-jre21-alpine rc-alpine" mutable 4.7.0-rc2 1 jre-alpine true
check "rc, older pre-release" "4.6.1-rc1-jdk 4.6.1-rc1-jdk21-noble" mutable 4.6.1-rc1 1 jdk-noble false
check "rc never gets minor, latest or legacy tags" "4.7.0-rc1 4.7.0-rc1-jre21-noble rc" mutable 4.7.0-rc1 1 jre-noble true true

check_fails "unknown variant" mutable 4.6.0 1 jdk-alpine
check_fails "unknown mode" moving 4.6.0 1 jre-noble
check_fails "revision 0" immutable 4.6.0 0 jre-noble
check_fails "version with a v" immutable v4.6.0 1 jre-noble
check_fails "two-part version" immutable 4.6 1 jre-noble
check_fails "missing arguments" immutable 4.6.0

if [ "$failures" -ne 0 ]; then
	echo "$failures test(s) failed"
	exit 1
fi
echo "All tags tests passed"
