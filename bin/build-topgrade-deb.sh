#!/bin/sh
# Build a Debian package of topgrade from its source, without the
# self-update feature, and drop it into the pool. Needs cargo (Rust 1.88 or
# newer) on the PATH.
#
#   bin/build-topgrade-deb.sh [version]
set -eu

VERSION="${1:-17.17.0}"
ARCH="amd64"
TARBALL="topgrade-${VERSION}.tar.gz"
URL="https://github.com/topgrade-rs/topgrade/archive/refs/tags/v${VERSION}.tar.gz"

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
POOL="$REPO_DIR/pool/main/t/topgrade"

if [ -n "${PUBLISHED_PACKAGES:-}" ] && "$REPO_DIR/bin/is-published.sh" "$PUBLISHED_PACKAGES" topgrade "$VERSION"; then
    echo "==> topgrade $VERSION already published"
    exit 0
fi
SUMS="$REPO_DIR/checksums/topgrade-${VERSION}.sha256"

for tool in curl tar dpkg-deb sha256sum cargo objdump; do
    command -v "$tool" >/dev/null || { echo "build-topgrade-deb.sh: $tool not found" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Fetching $TARBALL"
curl -fL --retry 3 -o "$WORK/$TARBALL" "$URL"

# The checksum is recorded the first time a version is built and verified on
# every build after that: an upstream release must not change under us.
if [ -f "$SUMS" ]; then
    echo "==> Verifying against $SUMS"
    ( cd "$WORK" && sha256sum -c "$SUMS" )
else
    mkdir -p "$REPO_DIR/checksums"
    ( cd "$WORK" && sha256sum "$TARBALL" > "$SUMS" )
    echo "==> Recorded $(cat "$SUMS")"
fi

tar -xzf "$WORK/$TARBALL" -C "$WORK"
SRC="$WORK/topgrade-${VERSION}"
echo "==> Building topgrade $VERSION"
( cd "$SRC" && CARGO_TARGET_DIR="$WORK/target" cargo build --locked --release )
BIN="$WORK/target/release/topgrade"
[ -f "$BIN" ] || { echo "build-topgrade-deb.sh: cargo built no topgrade binary" >&2; exit 1; }
GLIBC="$(objdump -T "$BIN" | sed -n 's/.*GLIBC_\([0-9.]*\).*/\1/p' | sort -V | tail -n 1)"

PKG="$WORK/pkg"
install -d "$PKG/DEBIAN" "$PKG/usr/bin" "$PKG/usr/share/doc/topgrade"
install -m 755 "$BIN" "$PKG/usr/bin/topgrade"
install -m 644 "$SRC/config.example.toml" "$PKG/usr/share/doc/topgrade/config.example.toml"

# --apparent-size: on a compressing filesystem such as ZFS, du otherwise
# reports the blocks allocated, and a 17 MB binary came out as 3 kB.
INSTALLED_KB="$(du -ks --apparent-size "$PKG/usr" | cut -f1)"
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: topgrade
Version: ${VERSION}
Section: admin
Priority: optional
Architecture: ${ARCH}
Maintainer: FreedomNAS Team <dev@freedomnas.io>
Installed-Size: ${INSTALLED_KB}
Depends: libc6 (>= ${GLIBC}), libgcc-s1
Homepage: https://github.com/topgrade-rs/topgrade
Description: Upgrade all the things
 Topgrade runs the update command of every package manager, language
 toolchain and container runtime it finds on the system, which is what
 FreedomNAS's Updates page drives.
 .
 Built from source without the self-update feature, so updates come only
 from APT.
CONTROL

cat > "$PKG/usr/share/doc/topgrade/copyright" <<'COPYRIGHT'
Upstream-Name: topgrade
Source: https://github.com/topgrade-rs/topgrade

Files: *
Copyright: topgrade-rs contributors
License: GPL-3+
 This program is free software: you can redistribute it and/or modify it
 under the terms of the GNU General Public License as published by the Free
 Software Foundation, either version 3 of the License, or (at your option)
 any later version.
 .
 On Debian systems the full text of the GNU General Public License version 3
 is in /usr/share/common-licenses/GPL-3.
COPYRIGHT

install -d "$POOL"
DEB="$POOL/topgrade_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$PKG" "$DEB" >/dev/null
echo "==> Built $DEB"
