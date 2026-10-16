#!/usr/bin/env bash
#
# Tests deploy/promote.sh against fake gh and docker commands, which keep the
# GitHub Releases, issues and the registry's tags in files.
#
# Usage: test/promote-test.sh

set -u -o pipefail

promote=$(cd "$(dirname "$0")/../deploy" && pwd)/promote.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

mkdir "$work/bin"
export FAKE="$work" PATH="$work/bin:$PATH" GITHUB_REPOSITORY=example/engine-docker IMAGE_REPOS="docker.io/example/engine"

# Fake gh: releases and issues are JSON arrays in $FAKE/releases.json and $FAKE/issues.json.
cat > "$work/bin/gh" << 'FAKE_GH'
#!/usr/bin/env bash
set -eu
cmd="$1 $2"
shift 2
jq_filter="." prerelease="" latest="" label="" notes_file="" comment=""
args=()
while [ $# -gt 0 ]; do
	case $1 in
		--jq) jq_filter=$2; shift ;;
		--label) label=$2; shift ;;
		--notes-file) notes_file=$2; shift ;;
		--body) comment=$2; shift ;;
		--json | --limit | -R | --state) shift ;;
		--prerelease=*) prerelease=${1#*=} ;;
		--latest=*) latest=${1#*=} ;;
		*) args+=("$1") ;;
	esac
	shift
done
# update <file> <jq arguments...>
update() {
	local file=$1
	shift
	jq "$@" "$FAKE/$file" > "$FAKE/$file.tmp"
	mv "$FAKE/$file.tmp" "$FAKE/$file"
}
case $cmd in
	"release list") jq -r "$jq_filter" "$FAKE/releases.json" ;;
	"release view") jq -r --arg t "${args[0]}" ".[] | select(.tagName == \$t) | $jq_filter" "$FAKE/releases.json" ;;
	"release edit")
		if [ -n "$prerelease" ]; then
			update releases.json --arg t "${args[0]}" --arg p "$prerelease" \
				'map(if .tagName == $t then .isPrerelease = ($p == "true") else . end)'
		fi
		if [ "$latest" = true ]; then
			update releases.json --arg t "${args[0]}" 'map(.isLatest = (.tagName == $t))'
		fi
		if [ -n "$notes_file" ]; then
			update releases.json --arg t "${args[0]}" --rawfile b /dev/stdin 'map(if .tagName == $t then .body = $b else . end)'
		fi
		;;
	"issue list")
		jq -r --arg l "$label" "[.[] | select(.state == \"open\" and (.labels | index(\$l)))] | $jq_filter" "$FAKE/issues.json"
		;;
	"issue view") jq -r --argjson n "${args[0]}" ".[] | select(.number == \$n) | $jq_filter" "$FAKE/issues.json" ;;
	"issue comment")
		update issues.json --argjson n "${args[0]}" --arg c "$comment" 'map(if .number == $n then .comments += [{body: $c}] else . end)'
		;;
	*) echo "fake gh: unsupported: $cmd" >&2; exit 1 ;;
esac
FAKE_GH

# Fake docker buildx imagetools: tags are "<repo:tag> <digest>" lines in $FAKE/tags.
cat > "$work/bin/docker" << 'FAKE_DOCKER'
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
FAKE_DOCKER
chmod +x "$work/bin/gh" "$work/bin/docker"

# publish <version> <revision> [hours ago] [soak hours]: what publish.yaml leaves
# behind, a candidate release and the immutable tags, with digest
# sha256:<version>-r<revision>-<variant>.
publish() {
	local version=$1 revision=$2 created soak=${4:-} variant tag
	created=$(date -u -d "${3:-0} hours ago" +%Y-%m-%dT%H:%M:%SZ)
	jq --arg t "$version-r$revision" --arg c "$created" --arg s "$soak" \
		'. + [{tagName: $t, isPrerelease: true, isDraft: false, createdAt: $c,
			body: ("Candidate notes" + (if $s != "" then "\n\nSoak: " + $s + " hours" else "" end))}]' \
		"$work/releases.json" > "$work/releases.tmp"
	mv "$work/releases.tmp" "$work/releases.json"
	for variant in jre-noble jdk-noble jre-alpine; do
		for tag in $("$(dirname "$promote")/tags.sh" immutable "$version" "$revision" "$variant"); do
			echo "docker.io/example/engine:$tag sha256:$version-r$revision-$variant" >> "$work/tags"
		done
	done
}

# issue <number> <state> <labels, comma separated> <title> <body>
issue() {
	jq --argjson n "$1" --arg s "$2" --arg l "$3" --arg t "$4" --arg b "$5" \
		'. + [{number: $n, state: $s, labels: ($l | split(",")), title: $t, body: $b, comments: []}]' \
		"$work/issues.json" > "$work/issues.tmp"
	mv "$work/issues.tmp" "$work/issues.json"
}

# set_issue <number> <jq update for that issue>
set_issue() {
	jq --argjson n "$1" "map(if .number == \$n then $2 else . end)" "$work/issues.json" > "$work/issues.tmp"
	mv "$work/issues.tmp" "$work/issues.json"
}

check() {
	if [ "$2" = "$3" ]; then
		echo "ok   - $1"
	else
		echo "FAIL - $1: got '$3', expected '$2'"
		failures=$((failures + 1))
	fi
}

# expect_tag <tag> <expected digest or "none">
expect_tag() {
	check "$1 -> $2" "$2" \
		"$(awk -v r="docker.io/example/engine:$1" '$1 == r { d = $2 } END { print d ? d : "none" }' "$work/tags")"
}

# expect_release <tag> <isPrerelease> [isLatest]
expect_release() {
	check "release $1: prerelease=$2 latest=${3:-false}" "$2 ${3:-false}" \
		"$(jq -r --arg t "$1" '.[] | select(.tagName == $t) | "\(.isPrerelease) \(.isLatest // false)"' "$work/releases.json")"
}

# expect_due <expected output of promote.sh due, lines joined with ";">
expect_due() {
	check "due: '$1'" "$1" "$("$promote" due 2> /dev/null | paste -sd ';')"
}

# run_promote <args...>: runs promote.sh, failing the test if it fails
run_promote() {
	if ! "$promote" "$@" > /dev/null 2> "$work/err"; then
		echo "FAIL - promote.sh $* exited non-zero"
		sed 's/^/       /' "$work/err"
		failures=$((failures + 1))
	fi
}

# expect_refused <name> <args...>
expect_refused() {
	local name=$1
	shift
	if "$promote" "$@" > /dev/null 2>&1; then
		echo "FAIL - $name"
		failures=$((failures + 1))
	else
		echo "ok   - $name"
	fi
}

reset() {
	echo '[]' > "$work/releases.json"
	echo '[]' > "$work/issues.json"
	: > "$work/tags"
}

reset

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

echo "# Soak"
reset
publish 4.8.0 1 47 48
expect_due ""
reset
publish 4.8.0 1 49 48
expect_due "4.8.0 1"
reset
publish 4.8.0 1 100
expect_due ""
SOAK_HOURS_FULL=0.1 expect_due "4.8.0 1"

echo "# A newer revision supersedes an older candidate, noted once"
reset
publish 4.8.0 1 200 48
publish 4.8.0 2 1 48
expect_due ""
"$promote" due > /dev/null 2>&1
check "superseded note added once" 1 \
	"$(jq -r '.[] | select(.tagName == "4.8.0-r1") | .body' "$work/releases.json" | grep -c '^Superseded by 4.8.0-r2')"

echo "# Blocking issues"
reset
publish 4.8.0 1 200 48
publish 4.9.0 1 200 48
issue 1 open release-blocker "Broken in 4.8.0" "details"
issue 2 open "" "Unlabelled, mentions 4.9.0" ""
issue 3 closed release-blocker "Closed, mentions 4.9.0" ""
issue 4 open bug,release-blocker "Only r2" "The 4.9.0-r2 image fails; 14.9.0 and 4.9.0.1 don't count"
expect_due "4.9.0 1"
"$promote" due > /dev/null 2>&1
check "blocked comment added once" 1 "$(jq '.[] | select(.number == 1) | .comments | length' "$work/issues.json")"
check "blocked note added once" 1 \
	"$(jq -r '.[] | select(.tagName == "4.8.0-r1") | .body' "$work/releases.json" | grep -cx 'Blocked by #1.')"
check "no comment on an unlabelled issue" 0 "$(jq '.[] | select(.number == 2) | .comments | length' "$work/issues.json")"
issue 5 open release-blocker "4.9.0-r1 fails" ""
expect_due ""
expect_refused "promote refuses a blocked revision" promote 4.9.0
FORCE=true run_promote promote 4.9.0
expect_release 4.9.0-r1 false true
set_issue 1 '.labels = []'
expect_due "4.8.0 1"
set_issue 1 '.labels = ["release-blocker"] | .state = "closed"'
expect_due "4.8.0 1"
issue 6 open release-blocker "4.8.0-rc1 problem" "a release candidate mention also blocks 4.8.0"
expect_due ""

echo "# Errors"
expect_refused "promoting a missing revision fails" promote 4.9.0 9

if [ "$failures" -ne 0 ]; then
	echo "$failures test(s) failed"
	exit 1
fi
echo "All promote tests passed"
