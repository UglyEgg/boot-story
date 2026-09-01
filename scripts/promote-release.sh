#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

tag=${1:-}
asset_dir=${2:-}
project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
version=$(sed -n 's/^project(BootStory VERSION \([0-9][0-9.]*\).*/\1/p' "$project_root/CMakeLists.txt")
test "$tag" = "v$version" || {
    printf 'Usage: %s v%s ASSET-DIR\n' "$0" "$version" >&2
    exit 2
}
test -d "$asset_dir"

"$project_root/scripts/release-manifest.sh" verify-complete "$asset_dir" "$version"
"$project_root/scripts/verify-release-signature.sh" \
    "$asset_dir/SHA256SUMS" "$asset_dir/SHA256SUMS.asc"
test "$(gh release view "$tag" --json isDraft --jq .isDraft)" = true || {
    printf 'Release %s is not a draft; refusing to mutate a public release.\n' "$tag" >&2
    exit 1
}

gh release upload "$tag" "$asset_dir/SHA256SUMS.asc" --clobber

verification_dir=$(mktemp -d)
trap 'rm -rf -- "$verification_dir"' EXIT HUP INT TERM
gh release download "$tag" --dir "$verification_dir"
"$project_root/scripts/release-manifest.sh" verify-complete "$verification_dir" "$version"
"$project_root/scripts/verify-release-signature.sh" \
    "$verification_dir/SHA256SUMS" "$verification_dir/SHA256SUMS.asc"

gh release edit "$tag" --draft=false
printf 'Published verified release %s.\n' "$tag"
