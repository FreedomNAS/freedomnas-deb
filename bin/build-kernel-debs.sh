#!/bin/sh
# Build the FreedomNAS kernel, its headers and the matching OpenZFS userspace
# from a linux-freedomnas checkout, and drop the packages into the pool.
#
#   bin/build-kernel-debs.sh                        # ../linux-freedomnas
#   bin/build-kernel-debs.sh /path/to/linux-freedomnas
#   INSTALL_BUILD_DEPS=1 bin/build-kernel-debs.sh   # apt-get build-dep first (root)
#   SKIP_PUBLISHED=1 COMPONENT=dev bin/build-kernel-debs.sh
#
# Versions, tarballs and checksums come from the checkout's PKGBUILD, the
# same file the Arch package is built from, so both editions ship the same
# kernel. The tarballs are downloaded into CACHE_DIR and verified here,
# before dpkg-buildpackage runs; the build itself needs no network.
#
# SKIP_PUBLISHED=1 does nothing when this version is already in the registry
# under COMPONENT: the kernel takes the better part of an hour to build.
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SRC="${1:-$(dirname "$REPO_DIR")/linux-freedomnas}"
CACHE_DIR="${CACHE_DIR:-$REPO_DIR/.cache}"
OWNER="${CODEBERG_OWNER:-FreedomNAS}"
DISTRIBUTION="${DISTRIBUTION:-trixie}"
COMPONENT="${COMPONENT:-main}"

[ -f "$SRC/PKGBUILD" ] && [ -d "$SRC/debian" ] || {
    echo "build-kernel-debs.sh: $SRC is not a linux-freedomnas checkout" >&2
    exit 1
}
for tool in bash curl dpkg-buildpackage dpkg-checkbuilddeps rsync sha256sum; do
    command -v "$tool" >/dev/null || {
        echo "build-kernel-debs.sh: $tool not found — run this in a Debian container" >&2
        exit 1
    }
done

pkgbuild() { bash -c 'source "$1/PKGBUILD" >/dev/null 2>&1; eval "echo \"\$$2\""' _ "$SRC" "$1"; }
version="$(pkgbuild pkgver)-$(pkgbuild pkgrel)"
echo "==> linux-freedomnas $version"

if [ -n "${SKIP_PUBLISHED:-}" ]; then
    url="https://codeberg.org/api/packages/$OWNER/debian/pool/$DISTRIBUTION/$COMPONENT/linux-image-freedomnas_${version}_amd64.deb"
    if [ "$(curl -s -o /dev/null -r 0-0 -w '%{http_code}' "$url")" = 206 ]; then
        echo "    already published in $DISTRIBUTION/$COMPONENT"
        exit 0
    fi
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tree="$WORK/linux-freedomnas"
rsync -a --exclude '.git' "$SRC/" "$tree/"

install -d "$CACHE_DIR"
bash -s "$SRC" "$CACHE_DIR" "$tree" <<'EOF'
set -eu
source "$1/PKGBUILD" >/dev/null 2>&1
for i in "${!source[@]}"; do
    src="${source[$i]}" sum="${sha256sums[$i]}"
    [ "$sum" = SKIP ] && continue
    file="${src##*/}"
    case "$src" in
        http*://*)
            if [ ! -f "$2/$file" ]; then
                curl -sSfL -o "$2/$file.part" "$src"
                mv "$2/$file.part" "$2/$file"
            fi
            echo "$sum  $2/$file" | sha256sum -c --quiet -
            cp "$2/$file" "$3/" ;;
        *)
            echo "$sum  $3/$file" | sha256sum -c --quiet - ;;
    esac
done
echo "${sha256sums_x86_64[0]}  $3/config.x86_64" | sha256sum -c --quiet -
EOF

( cd "$tree" && make -f debian/rules prepare >/dev/null )

if [ -n "${INSTALL_BUILD_DEPS:-}" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get build-dep -y --no-install-recommends "$tree"
fi
( cd "$tree" && dpkg-checkbuilddeps ) || {
    echo "build-kernel-debs.sh: missing build dependencies (above)" >&2
    exit 1
}
( cd "$tree" && dpkg-buildpackage -us -uc -b -j"$(nproc)" )

dest="$REPO_DIR/pool/main/l/linux-freedomnas"
install -d "$dest"
for deb in "$WORK"/*.deb; do
    mv "$deb" "$dest/"
    echo "    $dest/$(basename "$deb")"
done
