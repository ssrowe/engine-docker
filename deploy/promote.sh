#!/usr/bin/env bash
#
# Promotes an image revision: points the mutable tags from tags.sh at the
# revision's signed index in every repository in IMAGE_REPOS, then marks its
# GitHub Release as a full release. Nothing is rebuilt or re-signed. Run by
# promote.yaml; see docs/RELEASING.md, "Promoting".
#
# Usage: deploy/promote.sh plan <version> [revision]
#          Prints revision=, is_latest= and is_highest_in_minor= for promoting
#          <version>-r<revision>. The revision defaults to the newest one.
#        deploy/promote.sh promote <version> [revision]
#          Promotes it, then prints the same lines.
#
# Environment: GITHUB_REPOSITORY, IMAGE_REPOS, and GH_TOKEN for gh. Needs
# docker buildx and jq.

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

digest_of() {
	docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' | jq -r .digest
}

promote() {
	local version=$1 out revision is_latest is_highest_in_minor latest=false
	out=$(plan "$@")
	revision=$(sed -n 's/^revision=//p' <<< "$out")
	is_latest=$(sed -n 's/^is_latest=//p' <<< "$out")
	is_highest_in_minor=$(sed -n 's/^is_highest_in_minor=//p' <<< "$out")

	local repo variant source digest tag tags args
	for repo in $IMAGE_REPOS; do
		for variant in "${variants[@]}"; do
			source=$("$here/tags.sh" immutable "$version" "$revision" "$variant" | head -n 1)
			digest=$(digest_of "$repo:$source")
			mapfile -t tags < <("$here/tags.sh" mutable "$version" "$revision" "$variant" "$is_latest" "$is_highest_in_minor")
			args=()
			for tag in "${tags[@]}"; do
				args+=(-t "$repo:$tag")
			done
			# With a single index as the source, imagetools pushes that same index,
			# so the tags keep the signed digest.
			docker buildx imagetools create "${args[@]}" "$repo@$digest" >&2
			for tag in "${tags[@]}"; do
				if [ "$(digest_of "$repo:$tag")" != "$digest" ]; then
					fail "$repo:$tag doesn't point at $digest from $source"
				fi
			done
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
	*)
		echo "usage: $0 plan|promote <version> [revision]" >&2
		exit 2
		;;
esac
