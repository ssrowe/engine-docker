#!/usr/bin/env bash
#
# Promotes an image revision: points the mutable tags from tags.sh at the
# revision's signed index in every repository in IMAGE_REPOS, then marks its
# GitHub Release as a full release. Nothing is rebuilt or re-signed. Run by
# promote.yaml; see docs/RELEASING.md, "Promoting" and "Blocking a promotion".
#
# Usage: deploy/promote.sh plan <version> [revision]
#          Prints revision=, is_latest= and is_highest_in_minor= for promoting
#          <version>-r<revision>. The revision defaults to the newest one.
#        deploy/promote.sh promote <version> [revision]
#          Promotes it, then prints the same lines. Refuses while an open issue
#          labelled release-blocker mentions it, unless FORCE=true.
#        deploy/promote.sh due
#          Prints "<version> <revision>" for each candidate that has finished its
#          soak and isn't blocked. Notes superseded and blocked candidates in
#          their release notes, and comments once on each blocking issue.
#
# Environment: GITHUB_REPOSITORY, IMAGE_REPOS, GH_TOKEN for gh, and optionally
# FORCE and SOAK_HOURS_FULL (the soak for candidates whose notes don't give
# one; default 168). Needs docker buildx and jq.

set -eu -o pipefail

here=$(cd "$(dirname "$0")" && pwd)
variants=(jre-noble jdk-noble jre-alpine)

fail() {
	echo "promote.sh: $*" >&2
	exit 1
}

# "<tag> <isPrerelease>" for every published release of this repository.
releases() {
	gh release list -R "$GITHUB_REPOSITORY" --limit 1000 --json tagName,isPrerelease,isDraft \
		--jq '.[] | select(.isDraft | not) | "\(.tagName) \(.isPrerelease)"'
}

# newest_revision <releases> <version>
newest_revision() {
	awk -v v="$2" '{ n = substr($1, length(v) + 3) } index($1, v "-r") == 1 && n ~ /^[0-9]+$/ { print n }' <<< "$1" \
		| sort -n | tail -n 1
}

plan() {
	local version=$1 revision=${2:-} releases minor versions highest highest_in_minor=""
	if ! [[ $version =~ ^([0-9]+\.[0-9]+)\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
		fail "version must look like 4.6.0 or 4.7.0-rc1, without a v: '$version'"
	fi
	minor=${BASH_REMATCH[1]}
	releases=$(releases)
	revision=${revision:-$(newest_revision "$releases" "$version")}
	if ! awk -v t="$version-r$revision" '$1 == t { found = 1 } END { exit !found }' <<< "$releases"; then
		fail "there is no release $version-r$revision"
	fi
	# Versions that have a promoted revision, plus this one. Stable versions and
	# pre-releases are ranked separately: the rc tags follow the highest pre-release.
	versions=$( (awk '$2 == "false" { print $1 }' <<< "$releases" | sed 's/-r[0-9]*$//'; echo "$version") | sort -uV)
	if [[ $version == *-* ]]; then
		highest=$(grep -- - <<< "$versions" | tail -n 1)
	else
		highest=$(grep -v -- - <<< "$versions" | tail -n 1)
		highest_in_minor=$(grep -v -- - <<< "$versions" | awk -F. -v m="$minor" '$1 "." $2 == m' | tail -n 1)
	fi
	echo "revision=$revision"
	echo "is_latest=$([ "$highest" = "$version" ] && echo true || echo false)"
	echo "is_highest_in_minor=$([ "$highest_in_minor" = "$version" ] && echo true || echo false)"
}

# blocking_issues <version> <revision>: numbers of open release-blocker issues
# whose title or body mentions the version (blocking every revision) or this
# revision of it, e.g. 4.7.0 or 4.7.0-r2. 4.7.0-rc1 also counts as 4.7.0,
# which errs on the side of blocking.
blocking_issues() {
	local version=$1 revision=$2 number text mention
	gh issue list -R "$GITHUB_REPOSITORY" --label release-blocker --state open --limit 200 --json number,title,body \
		--jq '.[] | "\(.number)\t\(.title) \((.body // "") | gsub("[\\n\\r\\t]"; " "))"' \
		| while IFS=$'\t' read -r number text; do
			while read -r mention; do
				if [ "$mention" = "$version" ] || [ "$mention" = "$version-r$revision" ]; then
					echo "$number"
					break
				fi
			done < <(grep -oP "(?<![0-9.])\Q$version\E(-r[0-9]+)?(?![0-9.])" <<< "$text" || true)
		done
}

# note_once <release tag> <line>: adds a line to a release's notes unless it's there.
note_once() {
	local body
	body=$(gh release view "$1" -R "$GITHUB_REPOSITORY" --json body --jq .body)
	if ! grep -qxF -- "$2" <<< "$body"; then
		printf '%s\n\n%s\n' "$body" "$2" | gh release edit "$1" -R "$GITHUB_REPOSITORY" --notes-file - > /dev/null
	fi
}

# comment_once <issue> <text>: comments on an issue unless the same comment is there.
comment_once() {
	if ! gh issue view "$1" -R "$GITHUB_REPOSITORY" --json comments --jq '.comments[].body' | grep -qxF -- "$2"; then
		gh issue comment "$1" -R "$GITHUB_REPOSITORY" --body "$2" > /dev/null
	fi
}

due() {
	local releases now tag prerelease created version revision newest soak hours blockers number
	releases=$(gh release list -R "$GITHUB_REPOSITORY" --limit 1000 --json tagName,isPrerelease,isDraft,createdAt \
		--jq '.[] | select(.isDraft | not) | "\(.tagName) \(.isPrerelease) \(.createdAt)"')
	now=$(date -u +%s)
	while read -r tag prerelease created; do
		if [ "$prerelease" != true ] || ! [[ $tag =~ -r[0-9]+$ ]]; then
			continue
		fi
		version=${tag%-r*}
		revision=${tag##*-r}
		newest=$(newest_revision "$releases" "$version")
		if [ "$revision" != "$newest" ]; then
			note_once "$tag" "Superseded by $version-r$newest, so this candidate won't be promoted."
			continue
		fi
		soak=$(gh release view "$tag" -R "$GITHUB_REPOSITORY" --json body --jq .body | sed -n 's/^Soak: \([0-9.]*\) hours$/\1/p' | sed -n 1p)
		soak=${soak:-${SOAK_HOURS_FULL:-168}}
		hours=$(awk -v now="$now" -v t="$(date -u -d "$created" +%s)" 'BEGIN { printf "%.1f", (now - t) / 3600 }')
		if awk -v h="$hours" -v s="$soak" 'BEGIN { exit !(h < s) }'; then
			echo "$tag: soaking, $hours of $soak hours" >&2
			continue
		fi
		mapfile -t blockers < <(blocking_issues "$version" "$revision")
		if [ ${#blockers[@]} -gt 0 ]; then
			for number in "${blockers[@]}"; do
				comment_once "$number" "Promotion of \`$tag\` is blocked by this issue."
				note_once "$tag" "Blocked by #$number."
			done
			echo "$tag: blocked by ${blockers[*]/#/#}" >&2
			continue
		fi
		echo "$version $revision"
	done <<< "$releases"
}

digest_of() {
	docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' | jq -r .digest
}

promote() {
	local version=$1 out revision is_latest is_highest_in_minor latest=false
	out=$(plan "$@")
	revision=$(sed -n 's/^revision=//p' <<< "$out")
	is_latest=$(sed -n 's/^is_latest=//p' <<< "$out")
	is_highest_in_minor=$(sed -n 's/^is_highest_in_minor=//p' <<< "$out")

	local blockers
	blockers=$(blocking_issues "$version" "$revision" | sed 's/^/#/' | paste -sd ' ')
	if [ -n "$blockers" ] && [ "${FORCE:-false}" != true ]; then
		fail "$version-r$revision is blocked by release-blocker issue(s) $blockers. Close them, remove the label, or promote with force."
	elif [ -n "$blockers" ]; then
		echo "Promoting $version-r$revision despite release-blocker issue(s) $blockers (FORCE=true)" >&2
	fi

	local repo variant source digest tag tags args
	for repo in $IMAGE_REPOS; do
		for variant in "${variants[@]}"; do
			source=$("$here/tags.sh" immutable "$version" "$revision" "$variant" | sed -n 1p)
			digest=$(digest_of "$repo:$source")
			mapfile -t tags < <("$here/tags.sh" mutable "$version" "$revision" "$variant" "$is_latest" "$is_highest_in_minor")
			args=()
			for tag in "${tags[@]}"; do
				args+=(-t "$repo:$tag")
			done
			# With a single index as the source, imagetools pushes that same index,
			# so the tags keep the signed digest. One create sets every tag, so
			# checking one is enough; each check is a pull against Docker Hub's rate limit.
			docker buildx imagetools create "${args[@]}" "$repo@$digest" >&2
			if [ "$(digest_of "$repo:${tags[0]}")" != "$digest" ]; then
				fail "$repo:${tags[0]} doesn't point at $digest from $source"
			fi
			echo "$repo: ${tags[*]} -> $source ($digest)" >&2
		done
	done

	# Only stable versions can be GitHub's "latest" release, which the README badge shows.
	if [ "$is_latest" = true ] && [[ $version != *-* ]]; then
		latest=true
	fi
	gh release edit "$version-r$revision" -R "$GITHUB_REPOSITORY" --prerelease=false --latest="$latest" > /dev/null
	echo "$out"
}

case ${1:-} in
	plan) plan "${@:2}" ;;
	promote) promote "${@:2}" ;;
	due) due ;;
	*)
		echo "usage: $0 plan|promote <version> [revision], or $0 due" >&2
		exit 2
		;;
esac
