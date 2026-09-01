#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

manifest=${1:-}
signature=${2:-}
test -f "$manifest"
test -f "$signature"

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary_home=$(mktemp -d)
trap 'rm -rf -- "$temporary_home"' EXIT HUP INT TERM
chmod 0700 "$temporary_home"
GNUPGHOME="$temporary_home" gpg --batch --quiet --import \
    "$project_root/keys/uglyegg-release.asc"
verification=$(GNUPGHOME="$temporary_home" gpg --batch --status-fd=1 \
    --verify "$signature" "$manifest" 2>/dev/null) || exit 1

verified=false
while IFS= read -r fingerprint; do
    test -n "$fingerprint" || continue
    if awk -v expected="$fingerprint" '
        $2 == "VALIDSIG" && ($3 == expected || $NF == expected) { found = 1 }
        END { exit found ? 0 : 1 }
    ' <<EOF
$verification
EOF
    then
        verified=true
        break
    fi
done < "$project_root/keys/release-signing-fingerprints"
test "$verified" = true || {
    printf 'The manifest signature was not made by an allowed Boot Story release key.\n' >&2
    exit 1
}

printf 'Verified release manifest signature.\n'
