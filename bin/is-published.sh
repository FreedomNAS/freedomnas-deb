#!/bin/sh
# Exit 0 when <package> <version> is listed in an APT Packages file.
#
#   bin/is-published.sh Packages freedomnas-core 0.9.10+20261118095904.a54c544-1
set -eu

[ "$#" -eq 3 ] || { echo "usage: is-published.sh <Packages> <package> <version>" >&2; exit 2; }
[ -s "$1" ] || exit 1

awk -v p="$2" -v v="$3" '
    /^Package: / { pkg = $2 }
    /^Version: / { ver = $2 }
    /^$/ { if (pkg == p && ver == v) found = 1; pkg = ver = "" }
    END { if (pkg == p && ver == v) found = 1; exit !found }
' "$1"
