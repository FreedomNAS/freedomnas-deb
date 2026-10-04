#!/bin/sh
# Upload every .deb in the pool to Codeberg's Debian package registry.
#
#   CODEBERG_USER=<user> CODEBERG_TOKEN=<token> bin/publish-codeberg.sh
#   ... bin/publish-codeberg.sh pool/main/t/topgrade/topgrade_17.12.3_amd64.deb
#
# The token needs the `package` scope (write). Create it under
# Settings -> Applications -> Access Tokens. It is read from the environment
# and never written anywhere: curl takes it on stdin, so it stays out of the
# process list as well.
#
# Forgejo builds and signs the repository metadata itself, so dists/ and
# make-repo.sh are only for serving the pool as plain static files.
set -eu

OWNER="${CODEBERG_OWNER:-FreedomNAS}"
DISTRIBUTION="${DISTRIBUTION:-trixie}"
COMPONENT="${COMPONENT:-main}"
BASE="https://codeberg.org/api/packages/$OWNER/debian"

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

: "${CODEBERG_USER:?set CODEBERG_USER to your Codeberg username}"
: "${CODEBERG_TOKEN:?set CODEBERG_TOKEN to a token with the package scope}"
command -v curl >/dev/null || { echo "publish-codeberg.sh: curl not found" >&2; exit 1; }

if [ "$#" -gt 0 ]; then
    DEBS="$*"
else
    DEBS="$(find "$REPO_DIR/pool" -name '*.deb' | sort)"
fi
[ -n "$DEBS" ] || { echo "publish-codeberg.sh: no .deb in pool/" >&2; exit 1; }

for deb in $DEBS; do
    name="$(basename "$deb")"
    printf '==> %s\n' "$name"
    # --config -: curl reads the credentials from stdin, so the token never
    # appears in argv. A version already published is refused by the
    # registry; delete it there first, or build a new version.
    status="$(printf 'user = "%s:%s"\n' "$CODEBERG_USER" "$CODEBERG_TOKEN" \
        | curl --config - \
               --silent --show-error --output /dev/stderr \
               --write-out '%{http_code}' \
               --upload-file "$deb" \
               "$BASE/pool/$DISTRIBUTION/$COMPONENT/upload")"
    case "$status" in
        201|202) echo "    published" ;;
        409) echo "    already published at this version — delete it first, or bump the version" >&2 ;;
        *) echo "    HTTP $status" >&2; exit 1 ;;
    esac
done

cat <<EOF

Published to $BASE ($DISTRIBUTION/$COMPONENT).

On the FreedomNAS machine:

  curl -o /etc/apt/keyrings/freedomnas.asc $BASE/repository.key
  echo "deb [signed-by=/etc/apt/keyrings/freedomnas.asc] $BASE $DISTRIBUTION $COMPONENT" \\
      > /etc/apt/sources.list.d/freedomnas.list
  apt update && apt install freedomnas-webui
EOF
