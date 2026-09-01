#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

mode=${1:-}
asset_dir=${2:-}
version=${3:-}
case "$mode" in
    write|verify)
        action=$mode
        require_complete=false
        ;;
    write-complete|verify-complete)
        action=${mode%-complete}
        require_complete=true
        ;;
    *)
        printf 'Usage: %s {write|verify|write-complete|verify-complete} ASSET-DIR VERSION\n' "$0" >&2
        exit 2
        ;;
esac
test -d "$asset_dir"
case "$version" in
    ''|*[!0-9.]*) printf 'Invalid release version: %s\n' "$version" >&2; exit 2 ;;
esac

temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT HUP INT TERM
asset_names="$temporary_dir/assets"
expected_manifest="$temporary_dir/SHA256SUMS"
: > "$asset_names"
source_count=0
portable_count=0
deb_count=0
rpm_count=0

for asset_path in "$asset_dir"/*; do
    test -e "$asset_path" || continue
    if test -L "$asset_path"; then
        printf 'Release assets must not be symbolic links: %s\n' "$asset_path" >&2
        exit 1
    fi
    test -f "$asset_path" || continue
    asset_name=${asset_path##*/}
    case "$asset_name" in
        boot-story-"$version"-source.tar.gz)
            source_count=$((source_count + 1))
            printf '%s\n' "$asset_name" >> "$asset_names"
            ;;
        boot-story-"$version"-Linux-*.tar.gz)
            portable_count=$((portable_count + 1))
            printf '%s\n' "$asset_name" >> "$asset_names"
            ;;
        boot-story_"$version"-*.deb)
            deb_count=$((deb_count + 1))
            printf '%s\n' "$asset_name" >> "$asset_names"
            ;;
        boot-story-"$version"-*.rpm)
            rpm_count=$((rpm_count + 1))
            printf '%s\n' "$asset_name" >> "$asset_names"
            ;;
        SHA256SUMS|SHA256SUMS.asc) ;;
        *)
            printf 'Unexpected or mixed-version release asset: %s\n' "$asset_name" >&2
            exit 1
            ;;
    esac
done

LC_ALL=C sort -u -o "$asset_names" "$asset_names"
test -s "$asset_names" || {
    printf 'No Boot Story %s package assets found in %s\n' "$version" "$asset_dir" >&2
    exit 1
}
if test "$require_complete" = true &&
        ! { test "$source_count" -eq 1 &&
            test "$portable_count" -eq 1 &&
            test "$deb_count" -eq 1 &&
            test "$rpm_count" -eq 1; }; then
    printf '%s\n' \
        'A complete release requires exactly one source archive, portable archive, DEB, and RPM.' \
        "Found: source=$source_count portable=$portable_count deb=$deb_count rpm=$rpm_count" >&2
    exit 1
fi

(
    cd -- "$asset_dir"
    while IFS= read -r asset_name; do
        sha256sum -- "$asset_name"
    done < "$asset_names"
) > "$expected_manifest"

case "$action" in
    write)
        cp -- "$expected_manifest" "$asset_dir/SHA256SUMS"
        ;;
    verify)
        test -f "$asset_dir/SHA256SUMS"
        if ! cmp -s "$expected_manifest" "$asset_dir/SHA256SUMS"; then
            printf 'SHA256SUMS does not exactly describe the Boot Story %s asset set.\n' "$version" >&2
            diff -u "$expected_manifest" "$asset_dir/SHA256SUMS" >&2 || true
            exit 1
        fi
        (cd -- "$asset_dir" && sha256sum -c SHA256SUMS)
        ;;
esac
