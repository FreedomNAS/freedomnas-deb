#!/bin/sh
# Generate the APT metadata for whatever is in pool/.
#
#   bin/make-repo.sh                 # unsigned, for a quick local test
#   GPG_KEY=<key-id> bin/make-repo.sh  # signed: Release.gpg + InRelease
#
# apt-ftparchive comes from Debian's apt-utils. On a host that has no such
# package, run this inside a Debian container -- the pool is plain files and
# nothing here is host-specific.
set -eu

SUITE="${SUITE:-stable}"
COMPONENT="${COMPONENT:-main}"
ARCH="${ARCH:-amd64}"
ORIGIN="${ORIGIN:-FreedomNAS}"

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BINDIR="dists/$SUITE/$COMPONENT/binary-$ARCH"

command -v apt-ftparchive >/dev/null || {
    echo "make-repo.sh: apt-ftparchive not found -- install apt-utils, or run" >&2
    echo "              this inside a Debian container" >&2
    exit 1
}
[ -d "$REPO_DIR/pool" ] || { echo "make-repo.sh: nothing in pool/ yet" >&2; exit 1; }

cd "$REPO_DIR"
mkdir -p "$BINDIR"

echo "==> Packages"
apt-ftparchive --arch "$ARCH" packages pool > "$BINDIR/Packages"
gzip -9cn "$BINDIR/Packages" > "$BINDIR/Packages.gz"

echo "==> Release"
# Written aside and moved into place: a Release inside the directory being
# hashed -- the old one, or the empty file a redirection would create --
# ends up listed in its own hash tables.
rm -f "dists/$SUITE/Release" "dists/$SUITE/Release.gpg" "dists/$SUITE/InRelease"
RELEASE_TMP="$(mktemp)"
apt-ftparchive \
    -o "APT::FTPArchive::Release::Origin=$ORIGIN" \
    -o "APT::FTPArchive::Release::Label=$ORIGIN" \
    -o "APT::FTPArchive::Release::Suite=$SUITE" \
    -o "APT::FTPArchive::Release::Codename=$SUITE" \
    -o "APT::FTPArchive::Release::Architectures=$ARCH" \
    -o "APT::FTPArchive::Release::Components=$COMPONENT" \
    -o "APT::FTPArchive::Release::Description=Packages Debian does not carry, built for FreedomNAS" \
    release "dists/$SUITE" > "$RELEASE_TMP"
mv "$RELEASE_TMP" "dists/$SUITE/Release"

if [ -n "${GPG_KEY:-}" ]; then
    echo "==> Signing with $GPG_KEY"
    rm -f "dists/$SUITE/Release.gpg" "dists/$SUITE/InRelease"
    gpg --default-key "$GPG_KEY" --armor --detach-sign \
        -o "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"
    gpg --default-key "$GPG_KEY" --clearsign \
        -o "dists/$SUITE/InRelease" "dists/$SUITE/Release"
else
    echo "==> Unsigned: apt needs [trusted=yes] in sources.list for this repository"
fi

echo "==> $(grep -c '^Package:' "$BINDIR/Packages") package(s) in $SUITE/$COMPONENT/$ARCH"
