#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT HUP INT TERM
output="$temporary_dir/snapshot.json"

XDG_CACHE_HOME="$temporary_dir/cache" "$project_root/src/boot-story-snapshot" > "$output"

python3 - "$output" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    snapshot = json.load(handle)

assert snapshot["ok"] is True
assert snapshot["system"]["available"] is True
assert snapshot["system"]["totalMs"] > 0
assert isinstance(snapshot["system"]["stages"], list)
assert isinstance(snapshot["criticalPath"], list)
assert isinstance(snapshot["activations"], list)
assert snapshot["health"] in {"attention", "faster", "slower", "steady", "baseline", "unknown"}
assert isinstance(snapshot["failedUnitCount"], int)
assert isinstance(snapshot["coverage"]["failedUnitsAvailable"], bool)
PY

test -f "$temporary_dir/cache/boot-story/history.json"
test "$(stat -c '%a' "$temporary_dir/cache/boot-story/history.json")" = "600"

record_output="$temporary_dir/record-output"
XDG_CACHE_HOME="$temporary_dir/record-cache" "$project_root/src/boot-story-snapshot" --record-only > "$record_output"
test ! -s "$record_output"
test -f "$temporary_dir/record-cache/boot-story/history.json"

unit_output="$temporary_dir/unit.json"
"$project_root/src/boot-story-snapshot" --inspect-unit systemd-journald.service > "$unit_output"

python3 - "$unit_output" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    details = json.load(handle)

assert details["ok"] is True
assert details["unit"] == "systemd-journald.service"
assert isinstance(details["relationships"]["pulledInBy"], list)
assert isinstance(details["relationships"]["bringsIn"], list)
assert isinstance(details["result"], str)
PY
