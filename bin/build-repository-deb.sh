#!/bin/sh
# Build freedomnas-repository, the APT source and signing key of this
# repository for one component.
#
#   COMPONENT=main bin/build-repository-deb.sh [version]
set -eu

VERSION="${1:-1.0}"
COMPONENT="${COMPONENT:-main}"
DISTRIBUTION="${DISTRIBUTION:-trixie}"
OWNER="${CODEBERG_OWNER:-FreedomNAS}"
BASE="https://codeberg.org/api/packages/$OWNER/debian"

case "$COMPONENT" in
    main|dev) ;;
    *) echo "build-repository-deb.sh: COMPONENT must be main or dev, not $COMPONENT" >&2; exit 1 ;;
esac

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
POOL="$REPO_DIR/pool/$COMPONENT/f/freedomnas-repository"
SUMS="$REPO_DIR/checksums/repository-key.sha256"

for tool in curl dpkg-deb sha256sum; do
    command -v "$tool" >/dev/null || { echo "build-repository-deb.sh: $tool not found" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Fetching the registry's signing key"
curl -fsSL --retry 3 -o "$WORK/freedomnas-archive-keyring.asc" "$BASE/repository.key"
grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$WORK/freedomnas-archive-keyring.asc" \
    || { echo "build-repository-deb.sh: $BASE/repository.key is not a public key" >&2; exit 1; }

if [ -f "$SUMS" ]; then
    echo "==> Verifying against $SUMS"
    ( cd "$WORK" && sha256sum -c "$SUMS" )
else
    mkdir -p "$REPO_DIR/checksums"
    ( cd "$WORK" && sha256sum freedomnas-archive-keyring.asc > "$SUMS" )
    echo "==> Recorded $(cat "$SUMS")"
fi

PKG="$WORK/pkg"
install -d "$PKG/DEBIAN" "$PKG/usr/share/keyrings" "$PKG/etc/apt/sources.list.d" \
    "$PKG/usr/share/doc/freedomnas-repository"
install -m 644 "$WORK/freedomnas-archive-keyring.asc" "$PKG/usr/share/keyrings/freedomnas-archive-keyring.asc"
cat > "$PKG/etc/apt/sources.list.d/freedomnas.sources" <<SOURCES
Types: deb
URIs: $BASE
Suites: $DISTRIBUTION
Components: $COMPONENT
Signed-By: /usr/share/keyrings/freedomnas-archive-keyring.asc
SOURCES
echo /etc/apt/sources.list.d/freedomnas.sources > "$PKG/DEBIAN/conffiles"

cat > "$PKG/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
    legacy=/etc/apt/sources.list.d/freedomnas.list
    if [ -f "$legacy" ] && grep -q 'codeberg.org/api/packages/FreedomNAS/debian' "$legacy"; then
        rm -f "$legacy"
    fi
    if [ -z "$2" ]; then
        cat <<'EOF'

The FreedomNAS repository is configured. To install FreedomNAS:

  sudo apt update
  sudo apt install freedomnas-installer
  sudo freedomnas-install --mode inplace

EOF
    fi
fi
POSTINST
chmod 755 "$PKG/DEBIAN/postinst"

case "$COMPONENT" in
    main) CHANNEL="the releases (trixie main)" ;;
    dev) CHANNEL="the development snapshots (trixie dev)" ;;
esac
INSTALLED_KB="$(du -ks --apparent-size "$PKG/usr" "$PKG/etc" | awk '{s += $1} END {print s}')"
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: freedomnas-repository
Version: ${VERSION}
Section: admin
Priority: optional
Architecture: all
Maintainer: FreedomNAS Team <dev@freedomnas.io>
Installed-Size: ${INSTALLED_KB}
Depends: ca-certificates
Homepage: https://codeberg.org/FreedomNAS
Description: APT source and signing key of the FreedomNAS repository
 Configures APT to install FreedomNAS from its repository on Codeberg,
 following ${CHANNEL}. After installing it, run
 apt update and apt install freedomnas-installer.
CONTROL

cat > "$PKG/usr/share/doc/freedomnas-repository/copyright" <<'COPYRIGHT'
Files: *
Copyright: FreedomNAS Team
License: GPL-2+
 On Debian systems the full text of the GNU General Public License version 2
 is in /usr/share/common-licenses/GPL-2.
COPYRIGHT

install -d "$POOL"
DEB="$POOL/freedomnas-repository_${VERSION}_all.deb"
dpkg-deb --root-owner-group --build "$PKG" "$DEB" >/dev/null
echo "==> Built $DEB"
