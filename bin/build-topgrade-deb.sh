#!/bin/sh
# Build a Debian package from topgrade's upstream release binary.
#
# Debian does not package topgrade, and building it from source pulls the
# Rust toolchain and several hundred crates. Upstream publishes a statically
# linked musl binary, which needs no dependencies and no compiler: this
# wraps that binary in a .deb and drops it into the pool.
#
#   bin/build-topgrade-deb.sh [version]
set -eu

VERSION="${1:-17.12.3}"
ARCH="amd64"
TARBALL="topgrade-v${VERSION}-x86_64-unknown-linux-musl.tar.gz"
URL="https://github.com/topgrade-rs/topgrade/releases/download/v${VERSION}/${TARBALL}"

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
POOL="$REPO_DIR/pool/main/t/topgrade"
SUMS="$REPO_DIR/checksums/topgrade-${VERSION}.sha256"

for tool in curl tar dpkg-deb sha256sum; do
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
[ -f "$WORK/topgrade" ] || { echo "build-topgrade-deb.sh: no topgrade binary in $TARBALL" >&2; exit 1; }

PKG="$WORK/pkg"
install -d "$PKG/DEBIAN" "$PKG/usr/bin" "$PKG/usr/share/doc/topgrade"
install -m 755 "$WORK/topgrade" "$PKG/usr/bin/topgrade"

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
Homepage: https://github.com/topgrade-rs/topgrade
Description: Upgrade all the things
 Topgrade runs the update command of every package manager, language
 toolchain and container runtime it finds on the system, which is what
 FreedomNAS's Updates page drives.
 .
 This package ships upstream's statically linked release binary: it is not
 built from source and has no dependencies.
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
