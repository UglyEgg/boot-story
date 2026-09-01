#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
dist_dir=${DIST_DIR:-"$project_root/dist"}
checksum_file="$dist_dir/SHA256SUMS"
version=$(sed -n 's/^project(BootStory VERSION \([0-9][0-9.]*\).*/\1/p' "$project_root/CMakeLists.txt")
test -n "$version"
"$project_root/scripts/release-manifest.sh" verify-complete "$dist_dir" "$version"

signing_key=${RELEASE_SIGNING_KEY:-}
if test -z "$signing_key"; then
    signing_keys=$(gpg --batch --with-colons --list-secret-keys 2>/dev/null \
        | awk -F: '$1 == "sec" { print $5 }')
    key_count=$(printf '%s\n' "$signing_keys" | awk 'NF { count++ } END { print count + 0 }')
    if test "$key_count" -ne 1; then
        printf 'Found %s secret keys; set RELEASE_SIGNING_KEY explicitly.\n' "$key_count" >&2
        exit 1
    fi
    signing_key=$signing_keys
fi

primary_fingerprint=$(gpg --batch --with-colons --fingerprint "$signing_key" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print $10; exit }')
if ! rg -Fxq "$primary_fingerprint" "$project_root/keys/release-signing-fingerprints"; then
    printf 'Signing key %s is not an allowed Boot Story release key.\n' "$primary_fingerprint" >&2
    exit 1
fi

gpg --batch --yes --armor --detach-sign \
    --local-user "$signing_key" \
    --output "$checksum_file.asc" \
    "$checksum_file"

"$project_root/scripts/verify-release-signature.sh" "$checksum_file" "$checksum_file.asc"
printf 'Signed %s with %s\n' "$checksum_file" "$signing_key"
