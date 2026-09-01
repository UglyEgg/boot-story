#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

tag=${1:-}
version=${2:-}
main_ref=${3:-origin/main}
project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

test "$tag" = "v$version" || {
    printf 'Tag %s does not match version %s.\n' "$tag" "$version" >&2
    exit 1
}
test "$(git -C "$project_root" cat-file -t "refs/tags/$tag")" = tag || {
    printf 'Release tag %s must be an annotated, signed tag.\n' "$tag" >&2
    exit 1
}

verification=$(git -C "$project_root" verify-tag --raw "$tag" 2>&1) || {
    printf '%s\n' "$verification" >&2
    exit 1
}
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
    printf 'Release tag %s was not signed by an allowed Boot Story release key.\n' "$tag" >&2
    exit 1
}

git -C "$project_root" merge-base --is-ancestor "$tag^{}" "$main_ref" || {
    printf 'Release tag %s is not an ancestor of %s.\n' "$tag" "$main_ref" >&2
    exit 1
}

printf 'Verified signed tag %s on %s.\n' "$tag" "$main_ref"
