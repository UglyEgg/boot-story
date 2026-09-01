#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

if test "$#" -lt 1; then
    printf 'Usage: %s TOOL [ARGUMENT ...]\n' "$0" >&2
    exit 2
fi

tool=$1
shift
qt_bindir=

if command -v qtpaths6 >/dev/null 2>&1; then
    qt_bindir=$(qtpaths6 --query QT_INSTALL_BINS)
elif command -v qtpaths-qt6 >/dev/null 2>&1; then
    qt_bindir=$(qtpaths-qt6 --query QT_INSTALL_BINS)
fi

for candidate in "$tool-qt6" "$tool" "$qt_bindir/$tool"; do
    test "$candidate" != "/$tool" || continue
    if command -v "$candidate" >/dev/null 2>&1; then
        exec "$candidate" "$@"
    fi
done

printf 'Could not find the Qt 6 %s tool.\n' "$tool" >&2
exit 127
