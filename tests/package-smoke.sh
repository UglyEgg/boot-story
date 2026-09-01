#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

boot_story=${1:-boot-story}
temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT HUP INT TERM
helper="$temporary_dir/boot-story-snapshot"
log_file="$temporary_dir/boot-story.log"

printf '%s\n' '#!/bin/sh' \
    'printf '\''%s\n'\'' '\''{"ok":true,"timestampMs":1700000000000,"bootAgeMs":1000,"health":"baseline","summary":"Ready","system":{"available":true,"totalMs":10000,"readyTarget":"graphical.target","readyUserspaceMs":9000,"stages":[{"key":"userspace","label":"Services","durationMs":10000}]},"userSession":{"available":false,"totalMs":0,"stages":[]},"criticalPath":[],"criticalPathTotal":0,"activations":[],"activationTotal":0,"failedUnits":[],"failedUnitCount":0,"comparison":{},"recentBoots":[],"coverage":{"criticalPathAvailable":true,"activationsAvailable":true,"userSessionAvailable":false,"failedUnitsAvailable":true,"historyAvailable":true}}'\''' \
    > "$helper"
chmod 0700 "$helper"

set +e
xvfb-run -a timeout 3 "$boot_story" --helper "$helper" > "$log_file" 2>&1
status=$?
set -e
if test "$status" -ne 124; then
    printf 'Boot Story did not remain running in an offscreen package smoke test (status %s).\n' "$status" >&2
    cat "$log_file" >&2
    exit 1
fi
