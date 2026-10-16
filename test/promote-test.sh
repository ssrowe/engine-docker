#!/usr/bin/env bash
#
# Tests deploy/promote.sh against fake gh and docker commands, which keep the
# GitHub Releases and the registry's tags in files.
#
# Usage: test/promote-test.sh

set -u -o pipefail

promote=$(cd "$(dirname "$0")/../deploy" && pwd)/promote.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

mkdir "$work/bin"
export FAKE="$work" PATH="$work/bin:$PATH" GITHUB_REPOSITORY=example/engine-docker IMAGE_REPOS="docker.io/example/engine"

# Fake gh: releases are a JSON array in $FAKE/releases.json.
cat > "$work/bin/gh" << 'EOF'
#!/usr/bin/env bash
set -eu
cmd="$1 $2"
shift 2
jq_filter="." tag="" prerelease="" latest=""
args=()
while [ $# -gt 0 ]; do
	case $1 in
		--jq) jq_filter=$2; shift ;;
		--json | --limit | -R | --label | --state | --search) shift ;;
		--prerelease=*) prerelease=${1#*=} ;;
		--latest=*) latest=${1#*=} ;;
		*) args+=("$1") ;;
	esac
	shift
done
case $cmd in
	"release list") jq -r "$jq_filter" "$FAKE/releases.json" ;;
	"release edit")
		tag=${args[0]}
		jq --arg t "$tag" --arg p "$prerelease" --arg l "$latest" '
			map(if .tagName == $t then .isPrerelease = ($p == "true") else . end)
			| if $l == "true" then map(.isLatest = (.tagName == $t)) else . end' \
			"$FAKE/releases.json" > "$FAKE/releases.tmp"
		mv "$FAKE/releases.tmp" "$FAKE/releases.json"
		;;
	*) echo "fake gh: unsupported: $cmd" >&2; exit 1 ;;
esac
EOF

# Fake docker buildx imagetools: tags are "<repo:tag> <digest>" lines in $FAKE/tags.
cat > "$work/bin/docker" << 'EOF'
#!/usr/bin/env bash
set -eu
[ "$1 $2" = "buildx imagetools" ] || { echo "fake docker: unsupported: $*" >&2; exit 1; }
case $3 in
	inspect)
		digest=$(awk -v r="$4" '$1 == r { d = $2 } END { print d }' "$FAKE/tags")
		[ -n "$digest" ] || { echo "not found: $4" >&2; exit 1; }
		echo "{\"digest\": \"$digest\"}"
		;;
	create)
		shift 3
		tags=()
		while [ "$1" = -t ]; do tags+=("$2"); shift 2; done
		for t in "${tags[@]}"; do echo "$t ${1#*@}" >> "$FAKE/tags"; done
		;;
esac
EOF
chmod +x "$work/bin/gh" "$work/bin/docker"

# publish <version> <revision>: what publish.yaml leaves behind, a candidate
# release and the immutable tags, with digest sha256:<version>-r<revision>-<variant>.
publish() {
	local version=$1 revision=$2 variant tag
	jq --arg t "$version-r$revision" '. + [{tagName: $t, isPrerelease: true, isDraft: false}]' \
		"$work/releases.json" > "$work/releases.tmp"
	mv "$work/releases.tmp" "$work/releases.json"
	for variant in jre-noble jdk-noble jre-alpine; do
		for tag in $("$(dirname "$promote")/tags.sh" immutable "$version" "$revision" "$variant"); do
			echo "docker.io/example/engine:$tag sha256:$version-r$revision-$variant" >> "$work/tags"
		done
	done
}

# expect_tag <tag> <expected digest or "none">
expect_tag() {
	local actual
	actual=$(awk -v r="docker.io/example/engine:$1" '$1 == r { d = $2 } END { print d ? d : "none" }' "$work/tags")
	if [ "$actual" = "$2" ]; then
		echo "ok   - $1 -> $2"
	else
		echo "FAIL - $1 -> $actual, expected $2"
		failures=$((failures + 1))
	fi
}

# expect_release <tag> <isPrerelease> [isLatest]
expect_release() {
	local actual
	actual=$(jq -r --arg t "$1" '.[] | select(.tagName == $t) | "\(.isPrerelease) \(.isLatest // false)"' "$work/releases.json")
	if [ "$actual" = "$2 ${3:-false}" ]; then
		echo "ok   - release $1: prerelease=$2 latest=${3:-false}"
	else
		echo "FAIL - release $1: got prerelease/latest '$actual', expected '$2 ${3:-false}'"
		failures=$((failures + 1))
	fi
}

# run_promote <args...>: runs promote.sh, failing the test if it fails
run_promote() {
	if ! "$promote" "$@" > "$work/out" 2> "$work/err"; then
		echo "FAIL - promote.sh $* exited non-zero"
		sed 's/^/       /' "$work/err"
		failures=$((failures + 1))
	fi
}

echo '[]' > "$work/releases.json"
: > "$work/tags"

echo "# First promotion"
publish 4.6.0 1
run_promote promote 4.6.0
expect_tag 4.6.0 sha256:4.6.0-r1-jre-noble
expect_tag 4.6 sha256:4.6.0-r1-jre-noble
expect_tag latest sha256:4.6.0-r1-jre-noble
expect_tag latest-ubuntu sha256:4.6.0-r1-jre-noble
expect_tag latest-jdk sha256:4.6.0-r1-jdk-noble
expect_tag 4.6.0-alpine-jre sha256:4.6.0-r1-jre-alpine
expect_release 4.6.0-r1 false true

echo "# A new revision moves the tags"
publish 4.6.0 2
expect_tag latest sha256:4.6.0-r1-jre-noble
run_promote promote 4.6.0
expect_tag 4.6.0 sha256:4.6.0-r2-jre-noble
expect_tag latest-alpine sha256:4.6.0-r2-jre-alpine
expect_release 4.6.0-r2 false true

echo "# Rollback to r1"
run_promote promote 4.6.0 1
expect_tag 4.6.0 sha256:4.6.0-r1-jre-noble
expect_tag latest sha256:4.6.0-r1-jre-noble
expect_release 4.6.0-r1 false true

echo "# A release candidate moves rc but not latest"
publish 4.7.0-rc1 1
run_promote promote 4.7.0-rc1
expect_tag rc sha256:4.7.0-rc1-r1-jre-noble
expect_tag 4.7.0-rc1-jdk sha256:4.7.0-rc1-r1-jdk-noble
expect_tag latest sha256:4.6.0-r1-jre-noble
expect_release 4.7.0-rc1-r1 false
expect_release 4.6.0-r1 false true

echo "# 4.7.0 becomes latest"
publish 4.7.0 1
run_promote promote 4.7.0
expect_tag latest sha256:4.7.0-r1-jre-noble
expect_tag 4.7 sha256:4.7.0-r1-jre-noble
expect_tag rc sha256:4.7.0-rc1-r1-jre-noble
expect_release 4.7.0-r1 false true

echo "# A 4.6 patch after 4.7.0 moves 4.6 but not latest"
publish 4.6.1 1
run_promote promote 4.6.1
expect_tag 4.6 sha256:4.6.1-r1-jre-noble
expect_tag 4.6.1-jdk sha256:4.6.1-r1-jdk-noble
expect_tag latest sha256:4.7.0-r1-jre-noble
expect_release 4.6.1-r1 false
expect_release 4.7.0-r1 false true

echo "# Re-promoting an older patch doesn't move the minor tag back"
run_promote promote 4.6.0 2
expect_tag 4.6.0 sha256:4.6.0-r2-jre-noble
expect_tag 4.6 sha256:4.6.1-r1-jre-noble

echo "# Errors"
if "$promote" promote 4.6.0 9 > /dev/null 2>&1; then
	echo "FAIL - promoting a missing revision should fail"
	failures=$((failures + 1))
else
	echo "ok   - promoting a missing revision fails"
fi

if [ "$failures" -ne 0 ]; then
	echo "$failures test(s) failed"
	exit 1
fi
echo "All promote tests passed"
