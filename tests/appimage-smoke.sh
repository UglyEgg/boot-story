#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

appimage=${1:-}
test -x "$appimage"
appimage=$(realpath -- "$appimage")
project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT HUP INT TERM

version=$(sed -n 's/^project(BootStory VERSION \([0-9][0-9.]*\).*/\1/p' "$project_root/CMakeLists.txt")
test -n "$version"

version_output=$(HOME="$temporary_dir/home" \
    XDG_CONFIG_HOME="$temporary_dir/config" \
    APPIMAGE_EXTRACT_AND_RUN=1 \
    QT_QPA_PLATFORM=offscreen \
        "$appimage" --version)
printf '%s\n' "$version_output" | rg -Fq "Boot Story $version"

test -x "$temporary_dir/home/.local/libexec/boot-story/boot-story-snapshot"
test -f "$temporary_dir/config/systemd/user/boot-story-record.service"
test -f "$temporary_dir/config/systemd/user/boot-story-record.timer"
rg -Fq '%h/.local/libexec/boot-story/boot-story-snapshot' \
    "$temporary_dir/config/systemd/user/boot-story-record.service"

extract_dir="$temporary_dir/extracted"
mkdir -p -- "$extract_dir"
(
    cd -- "$extract_dir"
    "$appimage" --appimage-extract >/dev/null
)
test -f "$extract_dir/squashfs-root/usr/qml/org/kde/kirigami/qmldir"
test -f "$extract_dir/squashfs-root/usr/qml/org/kde/desktop/qmldir"
test -f "$extract_dir/squashfs-root/usr/plugins/platforms/libqoffscreen.so"
test -f "$extract_dir/squashfs-root/usr/plugins/platforms/libqxcb.so"
test -f "$extract_dir/squashfs-root/usr/plugins/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so"
test -f "$extract_dir/squashfs-root/usr/plugins/kf6/kirigami/platform/org.kde.desktop.so"
find "$extract_dir/squashfs-root/usr/plugins/platforms" -maxdepth 1 \
    \( -name 'libqwayland.so' -o -name 'libqwayland-egl.so' -o -name 'libqwayland-generic.so' \) \
    -print -quit | grep -q .
test -x "$extract_dir/squashfs-root/AppRun"
