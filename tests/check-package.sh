#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${1:-"$project_root/build"}
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT HUP INT TERM

DESTDIR="$stage" cmake --install "$build_dir" >/dev/null

test -x "$stage/usr/bin/boot-story"
test -x "$stage/usr/libexec/boot-story/boot-story-snapshot"
test -f "$stage/usr/share/applications/quest.entropy.bootstory.desktop"
test -f "$stage/usr/share/metainfo/quest.entropy.bootstory.metainfo.xml"
test -f "$stage/usr/share/icons/hicolor/scalable/apps/quest.entropy.bootstory.svg"
unit_dir=$(sed -n 's|^BOOT_STORY_SYSTEMD_USER_UNIT_DIR:PATH=||p' "$build_dir/CMakeCache.txt")
test -n "$unit_dir"
case "$unit_dir" in
    /*) staged_unit_dir="$stage$unit_dir" ;;
    *)
        install_prefix=$(sed -n 's|^CMAKE_INSTALL_PREFIX:PATH=||p' "$build_dir/CMakeCache.txt")
        test -n "$install_prefix"
        staged_unit_dir="$stage$install_prefix/$unit_dir"
        ;;
esac
test -f "$staged_unit_dir/boot-story-record.service"
test -f "$staged_unit_dir/boot-story-record.timer"

rg -q '^ExecStart=/usr/libexec/boot-story/boot-story-snapshot --record-only --history-file %C/boot-story/history\.json$' \
    "$staged_unit_dir/boot-story-record.service"
rg -q '^Unit=boot-story-record\.service$' "$staged_unit_dir/boot-story-record.timer"

version=$(sed -n 's/^project(BootStory VERSION \([0-9][0-9.]*\).*/\1/p' "$project_root/CMakeLists.txt")
test -n "$version"
QT_QPA_PLATFORM=offscreen "$stage/usr/bin/boot-story" --version | rg -Fq "Boot Story $version"
