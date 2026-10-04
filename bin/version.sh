#!/bin/sh
# Print the version a package should be built with.
#
#   bin/version.sh ../freedomnas-core              -> 0.9.9-1
#   bin/version.sh --snapshot ../freedomnas-core   -> 0.9.9+20261004155904.a54c544-1
#
# The base version is whatever debian/changelog says, and raising it — 0.9.9
# to 1.0 — stays a decision someone makes when the change deserves it. A
# snapshot keeps that base and appends the commit's UTC date and time and its
# hash, so every build of a small change gets a version of its own: the
# registry refuses to publish the same version twice, `0.9.9+...` sorts after
# `0.9.9-1` while staying below `1.0-1`, and two commits of the same day sort
# by time, never by their hashes.
set -eu

snapshot=0
if [ "${1:-}" = "--snapshot" ]; then
    snapshot=1
    shift
fi
src="${1:?usage: version.sh [--snapshot] <source-dir>}"
[ -f "$src/debian/changelog" ] || { echo "version.sh: no debian/changelog in $src" >&2; exit 1; }

base="$(sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' "$src/debian/changelog")"
[ -n "$base" ] || { echo "version.sh: cannot read the version from $src/debian/changelog" >&2; exit 1; }

if [ "$snapshot" = 0 ]; then
    printf '%s\n' "$base"
    exit 0
fi

command -v git >/dev/null || { echo "version.sh: git not found" >&2; exit 1; }
git -C "$src" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "version.sh: $src is not a git checkout, so there is no commit to name" >&2
    exit 1
}

upstream="${base%-*}"
revision="${base##*-}"
date="$(TZ=UTC git -C "$src" log -1 --format=%cd --date=format-local:%Y%m%d%H%M%S)"
sha="$(git -C "$src" log -1 --format=%h)"
printf '%s+%s.%s-%s\n' "$upstream" "$date" "$sha" "$revision"
