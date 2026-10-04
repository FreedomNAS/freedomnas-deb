#!/bin/sh
# Build the FreedomNAS packages from the checkouts beside this repository and
# drop them into the pool.
#
#   bin/build-freedomnas-debs.sh                     # all five
#   bin/build-freedomnas-debs.sh freedomnas-webui    # one of them
#   SNAPSHOT=1 bin/build-freedomnas-debs.sh          # ...at 1.0+<date>.<commit>
#
# A release build takes the version from debian/changelog. A snapshot build
# keeps that base and appends the commit it was built from, which is what
# every automatic rebuild uses: the registry refuses a version it already
# has, and raising the base version stays a deliberate act.
#
# Each source tree is copied to a temporary directory first: dpkg-buildpackage
# writes its artifacts next to the tree it builds, and a git checkout is not
# somewhere to leave them.
#
# Needs Debian's packaging tooling (dpkg-dev, debhelper, fakeroot and, for
# freedomnas-core, python3-all, python3-setuptools and
# pybuild-plugin-pyproject), so it runs inside a Debian container on a host
# that is not Debian.
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SRC_ROOT="$(dirname "$REPO_DIR")"
DEFAULT_COMPONENTS="freedomnas-profiles freedomnas-core freedomnas-docs freedomnas-webui freedomnas-installer"
COMPONENTS="${*:-$DEFAULT_COMPONENTS}"

for tool in dpkg-buildpackage dpkg-checkbuilddeps fakeroot rsync; do
    command -v "$tool" >/dev/null || {
        echo "build-freedomnas-debs.sh: $tool not found — install dpkg-dev," >&2
        echo "  debhelper, fakeroot and rsync, or run this in a Debian container" >&2
        exit 1
    }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for name in $COMPONENTS; do
    src="$SRC_ROOT/$name"
    [ -d "$src/debian" ] || { echo "build-freedomnas-debs.sh: no debian/ in $src" >&2; exit 1; }

    version="$("$(dirname -- "$0")/version.sh" ${SNAPSHOT:+--snapshot} "$src")"
    echo "==> $name $version"
    rsync -a --exclude '.git' --exclude '__pycache__' "$src/" "$WORK/$name/"

    # The copy's changelog carries the version this build is published under;
    # the checkout's own changelog is left alone.
    sed -i "1s/^\([^(]*\)([^)]*)/\1($version)/" "$WORK/$name/debian/changelog"

    if [ -n "${SNAPSHOT:-}" ]; then echo dev; else echo main; fi > "$WORK/$name/CHANNEL"

    ( cd "$WORK/$name" && dpkg-checkbuilddeps ) || {
        echo "build-freedomnas-debs.sh: $name is missing build dependencies (above)" >&2
        exit 1
    }
    ( cd "$WORK/$name" && dpkg-buildpackage -us -uc -b >/dev/null )

    letter="$(printf '%s' "$name" | cut -c1)"
    dest="$REPO_DIR/pool/main/$letter/$name"
    install -d "$dest"
    for deb in "$WORK"/*.deb; do
        [ -f "$deb" ] || continue
        mv "$deb" "$dest/"
        echo "    $dest/$(basename "$deb")"
    done
    rm -f "$WORK"/*.buildinfo "$WORK"/*.changes
done

echo "==> Now run bin/make-repo.sh"
