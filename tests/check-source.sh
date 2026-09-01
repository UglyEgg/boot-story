#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
pycache_dir=$(mktemp -d)
trap 'rm -rf -- "$pycache_dir"' EXIT HUP INT TERM

PYTHONPYCACHEPREFIX="$pycache_dir" python3 -m py_compile "$project_root/src/boot-story-snapshot"

test -x "$project_root/src/boot-story-snapshot"
test -f "$project_root/src/main.cpp"
test -f "$project_root/src/backend/BootStoryBackend.cpp"
test -f "$project_root/src/qml/Main.qml"
test -f "$project_root/data/quest.entropy.bootstory.desktop"
test -f "$project_root/data/quest.entropy.bootstory.metainfo.xml"
test -f "$project_root/data/systemd/boot-story-record.service.in"
test -f "$project_root/data/systemd/boot-story-record.timer"
test -f "$project_root/.github/workflows/ci.yml"
test -x "$project_root/tests/check-release.sh"
test -x "$project_root/tests/package-smoke.sh"
test -x "$project_root/scripts/build-release.sh"
test -x "$project_root/scripts/run-qml-tool.sh"
test -x "$project_root/scripts/release-manifest.sh"
test -x "$project_root/scripts/verify-release-tag.sh"
test -x "$project_root/scripts/verify-release-signature.sh"
test -x "$project_root/scripts/sign-release.sh"
test -x "$project_root/scripts/promote-release.sh"
test -f "$project_root/keys/uglyegg-release.asc"
test -f "$project_root/keys/release-signing-fingerprints"

rg -q '^Exec=boot-story$' "$project_root/data/quest.entropy.bootstory.desktop"
rg -q '<id>quest\.entropy\.bootstory</id>' "$project_root/data/quest.entropy.bootstory.metainfo.xml"
rg -q 'Type=oneshot' "$project_root/data/systemd/boot-story-record.service.in"
rg -q '^OnActiveSec=15s$' "$project_root/data/systemd/boot-story-record.timer"
rg -q '^WantedBy=graphical-session\.target$' "$project_root/data/systemd/boot-story-record.timer"
if rg -q '^WantedBy=graphical-session\.target$' "$project_root/data/systemd/boot-story-record.service.in"; then
    printf 'The recorder service must not be wanted by the target it orders after.\n' >&2
    exit 1
fi
rg -q 'setHistoryCollectionEnabled' "$project_root/src/backend/BootStoryBackend.h"
rg -Fq 'QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"))' "$project_root/src/main.cpp"
rg -Fq 'Kirigami.Theme.colorSet: Kirigami.Theme.Window' "$project_root/src/qml/Main.qml"
rg -q 'CPACK_DEBIAN_PACKAGE_DEPENDS' "$project_root/CMakeLists.txt"
rg -q 'CPACK_RPM_PACKAGE_REQUIRES' "$project_root/CMakeLists.txt"
rg -q 'container: ubuntu:26\.04' "$project_root/.github/workflows/ci.yml"
rg -q 'container: fedora:44' "$project_root/.github/workflows/ci.yml"

if rg -n '^[[:space:]]*uses:[[:space:]]+[^[:space:]]+@' "$project_root/.github" \
        | rg -v '@[0-9a-f]{40}([[:space:]]|$)'; then
    printf 'GitHub Actions must be pinned to full commit hashes.\n' >&2
    exit 1
fi

find "$project_root/src/qml" -type f \( -name '*.qml' -o -name '*.js' \) \
    -printf 'src/qml/%f\n' | sort > "$pycache_dir/qml-files"
sed -n '/^set(BOOT_STORY_QML_FILES$/,/^)/p' "$project_root/CMakeLists.txt" \
    | sed -n 's/^[[:space:]]*\(src\/qml\/[^[:space:]]*\)[[:space:]]*$/\1/p' \
    | sort > "$pycache_dir/qml-resources"
if ! cmp -s "$pycache_dir/qml-files" "$pycache_dir/qml-resources"; then
    printf 'Every QML and JavaScript source must be present in BOOT_STORY_QML_FILES.\n' >&2
    diff -u "$pycache_dir/qml-files" "$pycache_dir/qml-resources" >&2 || true
    exit 1
fi

version=$(sed -n 's/^project(BootStory VERSION \([0-9][0-9.]*\).*/\1/p' "$project_root/CMakeLists.txt")
test -n "$version"
rg -Fq "<release version=\"$version\"" "$project_root/data/quest.entropy.bootstory.metainfo.xml"
rg -Fq "## $version" "$project_root/CHANGELOG.md"
rg -Fq 'BOOT_STORY_VERSION' "$project_root/src/main.cpp"

if rg -n --glob '*.py' --glob '*.qml' --glob '*.js' \
        'shell=True|eval\(|exec\(|https?://|socket\.' "$project_root/src"; then
    printf 'Unexpected execution or network primitive found in packaged contents.\n' >&2
    exit 1
fi


if rg -n --glob '*.cpp' --glob '*.h' \
        'QNetwork|QTcpSocket|QUdpSocket|QDesktopServices::openUrl' "$project_root/src"; then
    printf 'Unexpected network primitive found in packaged C++ contents.\n' >&2
    exit 1
fi

if command -v appstreamcli >/dev/null 2>&1; then
    if ! appstreamcli validate --no-net "$project_root/data/quest.entropy.bootstory.metainfo.xml" >/dev/null; then
        appstreamcli validate --no-net "$project_root/data/quest.entropy.bootstory.metainfo.xml"
        exit 1
    fi
fi
