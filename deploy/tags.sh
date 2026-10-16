#!/usr/bin/env bash
#
# Prints the tags for one variant of one image revision, one per line, without
# the repository. publish.yaml writes the immutable tags when it pushes a
# revision; promote.yaml moves the mutable tags to a revision. It only prints;
# the workflows decide is_latest and is_highest_in_minor.
#
# Usage: deploy/tags.sh <mode> <version> <revision> <variant> [is_latest] [is_highest_in_minor]
#   mode                 immutable (4.6.0-r1, ...) or mutable (4.6.0, 4.6, latest, ...)
#   version              upstream OIE version, e.g. 4.6.0 or 4.7.0-rc1
#   revision             image revision, the N in -rN
#   variant              jre-noble, jdk-noble or jre-alpine
#   is_latest            true for the highest promoted version: the highest stable
#                        version, or for a pre-release the highest pre-release
#   is_highest_in_minor  true for the highest promoted patch of its minor (stable only)
#
# The tag scheme is described in README.md ("Supported tags") and
# docs/RELEASING.md ("Tags"). test/tags-test.sh covers it.

set -eu -o pipefail

usage() {
	echo "usage: $0 immutable|mutable <version> <revision> <variant> [is_latest] [is_highest_in_minor]" >&2
	exit 2
}

[ $# -ge 4 ] || usage
mode=$1 version=$2 revision=$3 variant=$4 is_latest=${5:-false} is_highest_in_minor=${6:-false}

[[ $version =~ ^([0-9]+)\.([0-9]+)\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || usage
minor="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
prerelease=${BASH_REMATCH[3]}
[[ $revision =~ ^[1-9][0-9]*$ ]] || usage

# Every variant has a short tag suffix and a long one naming the Java version and
# OS; the default variant's short suffix is empty. Legacy suffixes keep the tags
# of the original images moving.
java=21
case $variant in
	jre-noble) short="" legacy=(ubuntu ubuntu-jre) ;;
	jdk-noble) short="-jdk" legacy=(ubuntu-jdk) ;;
	jre-alpine) short="-alpine" legacy=(alpine-jre) ;;
	*) usage ;;
esac
long="-${variant/-/$java-}"

case $mode in
	immutable)
		echo "$version$short-r$revision"
		echo "$version$long-r$revision"
		;;
	mutable)
		echo "$version$short"
		echo "$version$long"
		if [ -n "$prerelease" ]; then
			if [ "$is_latest" = true ]; then
				echo "rc$short"
			fi
		else
			for suffix in "${legacy[@]}"; do
				echo "$version-$suffix"
			done
			if [ "$is_highest_in_minor" = true ]; then
				echo "$minor$short"
			fi
			if [ "$is_latest" = true ]; then
				echo "latest$short"
				for suffix in "${legacy[@]}"; do
					echo "latest-$suffix"
				done
			fi
		fi
		;;
	*) usage ;;
esac
