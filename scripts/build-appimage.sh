#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
output_dir=${1:-"$project_root/dist"}
tool_cache=${APPIMAGE_TOOL_CACHE_DIR:-"$project_root/.cache/appimage-tools"}
temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT HUP INT TERM

architecture=$(uname -m)
test "$architecture" = x86_64 || {
    printf 'Boot Story AppImages currently support x86_64 builders only.\n' >&2
    exit 1
}

version=$(sed -n 's/^project(BootStory VERSION \([0-9][0-9.]*\).*/\1/p' "$project_root/CMakeLists.txt")
test -n "$version"

linuxdeploy_name=linuxdeploy-x86_64.AppImage
qt_plugin_name=linuxdeploy-plugin-qt-x86_64.AppImage
linuxdeploy_url=https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/$linuxdeploy_name
qt_plugin_url=https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/$qt_plugin_name
linuxdeploy_sha256=36a2d7e274d12e1050d0e9ecfe11d339ed54720b2bec464c286d53f8b07f5c62
qt_plugin_sha256=cfc1055b2b9dbc08412b579f20990b7b41a17b61beaa5847dc9477c96c9e9617

fetch_tool()
{
    tool_name=$1
    tool_url=$2
    expected_sha256=$3
    tool_path="$tool_cache/$tool_name"

    mkdir -p -- "$tool_cache"
    if ! test -f "$tool_path" \
        || ! printf '%s  %s\n' "$expected_sha256" "$tool_path" | sha256sum --check --status; then
        temporary_tool="$temporary_dir/$tool_name"
        curl --fail --location --retry 3 --output "$temporary_tool" "$tool_url"
        printf '%s  %s\n' "$expected_sha256" "$temporary_tool" | sha256sum --check --status
        chmod 0755 "$temporary_tool"
        mv -f -- "$temporary_tool" "$tool_path"
    fi
    chmod 0755 "$tool_path"
}

fetch_tool "$linuxdeploy_name" "$linuxdeploy_url" "$linuxdeploy_sha256"
fetch_tool "$qt_plugin_name" "$qt_plugin_url" "$qt_plugin_sha256"

appdir="$temporary_dir/AppDir"
build_dir=${APPIMAGE_BUILD_DIR:-"$project_root/build-appimage"}
cmake \
    -S "$project_root" \
    -B "$build_dir" \
    -G Ninja \
    -DBUILD_TESTING=OFF \
    -DBOOT_STORY_INSTALL_SYSTEMD_UNITS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr >/dev/null
cmake --build "$build_dir" >/dev/null
DESTDIR="$appdir" cmake --install "$build_dir" >/dev/null

install -D -m 0644 \
    "$project_root/data/systemd/boot-story-record-portable.service" \
    "$appdir/usr/share/boot-story/portable/boot-story-record.service"
install -D -m 0644 \
    "$project_root/data/systemd/boot-story-record.timer" \
    "$appdir/usr/share/boot-story/portable/boot-story-record.timer"

qt_plugins_dir=$(qtpaths6 --query QT_INSTALL_PLUGINS)
wayland_egl_plugin="$qt_plugins_dir/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so"
kirigami_desktop_plugin="$qt_plugins_dir/kf6/kirigami/platform/org.kde.desktop.so"
test -f "$wayland_egl_plugin"
test -f "$kirigami_desktop_plugin"
install -D -m 0644 "$wayland_egl_plugin" \
    "$appdir/usr/plugins/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so"
install -D -m 0644 "$kirigami_desktop_plugin" \
    "$appdir/usr/plugins/kf6/kirigami/platform/org.kde.desktop.so"

# The KDE Controls style is selected from C++, so give qmlimportscanner one
# packaging-only source that makes this runtime dependency explicit.
qml_scan_dir="$temporary_dir/qml-scan"
mkdir -p -- "$qml_scan_dir"
printf '%s\n' 'import org.kde.desktop' 'QtObject {}' > "$qml_scan_dir/DesktopStyle.qml"

mkdir -p -- "$output_dir"
output_file="$output_dir/boot-story-$version-x86_64.AppImage"
rm -f -- "$output_file"

plugin_dir="$temporary_dir/plugins"
mkdir -p -- "$plugin_dir"
cp -- "$tool_cache/$linuxdeploy_name" "$plugin_dir/$linuxdeploy_name"
cp -- "$project_root/appimage/linuxdeploy-plugin-qt-wrapper" "$plugin_dir/linuxdeploy-plugin-qt"
chmod 0755 "$plugin_dir/$linuxdeploy_name" "$plugin_dir/linuxdeploy-plugin-qt"

qt_platform_dir=$qt_plugins_dir/platforms
extra_platform_plugins=
for platform_plugin in \
        libqoffscreen.so \
        libqwayland.so \
        libqwayland-egl.so \
        libqwayland-generic.so; do
    if test -f "$qt_platform_dir/$platform_plugin"; then
        if test -n "$extra_platform_plugins"; then
            extra_platform_plugins="$extra_platform_plugins;$platform_plugin"
        else
            extra_platform_plugins=$platform_plugin
        fi
    fi
done
printf '%s' "$extra_platform_plugins" | grep -q 'libqoffscreen\.so'
printf '%s' "$extra_platform_plugins" | grep -q 'libqwayland'

source_date_epoch=${SOURCE_DATE_EPOCH:-$(git -C "$project_root" log -1 --format=%ct)}

deployment_log="$temporary_dir/linuxdeploy.log"
if ! PATH="$plugin_dir:$PATH" \
    APPIMAGE_EXTRACT_AND_RUN=1 \
    BOOT_STORY_QT_PLUGIN="$tool_cache/$qt_plugin_name" \
    EXTRA_PLATFORM_PLUGINS="$extra_platform_plugins" \
    NO_STRIP=1 \
    QML_SOURCES_PATHS="$project_root/src/qml:$qml_scan_dir" \
    SOURCE_DATE_EPOCH="$source_date_epoch" \
    LDAI_OUTPUT="$output_file" \
    LINUXDEPLOY_OUTPUT_VERSION="$version" \
        "$plugin_dir/$linuxdeploy_name" \
            --appdir "$appdir" \
            --desktop-file "$project_root/data/quest.entropy.bootstory.desktop" \
            --icon-file "$project_root/data/icons/hicolor/scalable/apps/quest.entropy.bootstory.svg" \
            --custom-apprun "$project_root/appimage/AppRun" \
            --exclude-library 'libXau.so*' \
            --exclude-library 'libXdmcp.so*' \
            "--deploy-deps-only=$appdir/usr/plugins/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so" \
            "--deploy-deps-only=$appdir/usr/plugins/kf6/kirigami/platform/org.kde.desktop.so" \
            --plugin qt \
            --output appimage >"$deployment_log" 2>&1; then
    tail -n 200 "$deployment_log" >&2
    exit 1
fi

test -x "$output_file"
printf 'Created %s\n' "$output_file"
