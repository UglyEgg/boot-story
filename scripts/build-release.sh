#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

requested_format=${1:-tgz}
case "$requested_format" in
    all|deb|rpm|source|tgz) ;;
    *)
        printf 'Usage: %s [all|deb|rpm|source|tgz]\n' "$0" >&2
        exit 2
        ;;
esac

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
dist_dir=${DIST_DIR:-"$project_root/dist"}
temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT HUP INT TERM

version=$(sed -n 's/^project(BootStory VERSION \([0-9][0-9.]*\).*/\1/p' "$project_root/CMakeLists.txt")
test -n "$version"

build_dir=${RELEASE_BUILD_DIR:-"$project_root/build-release"}
package_dir="$temporary_dir/packages"
mkdir -p -- "$package_dir"

generators=
include_source=false
case "$requested_format" in
    all)
        generators='TGZ DEB RPM'
        include_source=true
        ;;
    deb) generators='DEB' ;;
    rpm) generators='RPM' ;;
    source) include_source=true ;;
    tgz) generators='TGZ' ;;
esac

source_date_epoch=${SOURCE_DATE_EPOCH:-$(git -C "$project_root" log -1 --format=%ct)}
case " $generators " in
    *' DEB '*)
        command -v dpkg-shlibdeps >/dev/null 2>&1 || {
            printf 'Debian packages must be built with dpkg-shlibdeps available; use the Ubuntu CI job or install dpkg-dev.\n' >&2
            exit 1
        }
        ;;
esac
case " $generators " in
    *' RPM '*)
        command -v rpmbuild >/dev/null 2>&1 || {
            printf 'RPM packages must be built with rpmbuild available; use the Fedora CI job or install rpm-build.\n' >&2
            exit 1
        }
        ;;
esac
if test -n "$generators"; then
    cmake \
        -S "$project_root" \
        -B "$build_dir" \
        -G Ninja \
        -DBUILD_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr >/dev/null
    cmake --build "$build_dir" >/dev/null
fi

for generator in $generators; do
    SOURCE_DATE_EPOCH="$source_date_epoch" \
        cpack -G "$generator" --config "$build_dir/CPackConfig.cmake" -B "$package_dir" >/dev/null
done

if "$include_source"; then
    if test -n "$(git -C "$project_root" status --porcelain --untracked-files=normal)"; then
        printf 'Refusing to create a source release from a dirty worktree.\n' >&2
        exit 1
    fi
    source_base="boot-story-$version-source"
    git -C "$project_root" archive \
        --format=tar \
        --prefix="boot-story-$version/" \
        --output="$temporary_dir/$source_base.tar" \
        HEAD
    gzip -n "$temporary_dir/$source_base.tar"
    mv -- "$temporary_dir/$source_base.tar.gz" "$package_dir/$source_base.tar.gz"
fi

mkdir -p -- "$dist_dir"

# A dist directory may accumulate formats from separate native build hosts, but
# it must never mix versions. Preserve only current-version artifacts, then
# replace the format requested by this invocation.
find "$dist_dir" -maxdepth 1 -type f \
    \( -name 'boot-story-*.tar.gz' -o -name 'boot-story_*.deb' -o -name 'boot-story-*.rpm' \) \
    ! -name "boot-story-$version-source.tar.gz" \
    ! -name "boot-story-$version-Linux-*.tar.gz" \
    ! -name "boot-story_${version}-*.deb" \
    ! -name "boot-story-${version}-*.rpm" \
    -delete
case "$requested_format" in
    all)
        find "$dist_dir" -maxdepth 1 -type f \
            \( -name 'boot-story-*.tar.gz' -o -name 'boot-story_*.deb' -o -name 'boot-story-*.rpm' \) \
            -delete
        ;;
    deb) find "$dist_dir" -maxdepth 1 -type f -name 'boot-story_*.deb' -delete ;;
    rpm) find "$dist_dir" -maxdepth 1 -type f -name 'boot-story-*.rpm' -delete ;;
    source) find "$dist_dir" -maxdepth 1 -type f -name 'boot-story-*-source.tar.gz' -delete ;;
    tgz)
        find "$dist_dir" -maxdepth 1 -type f -name 'boot-story-*.tar.gz' \
            ! -name 'boot-story-*-source.tar.gz' -delete
        ;;
esac
find "$dist_dir" -maxdepth 1 -type f \( -name 'SHA256SUMS' -o -name 'SHA256SUMS.asc' \) -delete

artifact_count=0
for artifact in "$package_dir"/*; do
    test -f "$artifact" || continue
    cp -- "$artifact" "$dist_dir/"
    artifact_count=$((artifact_count + 1))
done
test "$artifact_count" -gt 0

"$project_root/scripts/release-manifest.sh" write "$dist_dir" "$version"

printf 'Created %s package artifact(s) in %s\n' "$artifact_count" "$dist_dir"
