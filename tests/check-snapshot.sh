#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT HUP INT TERM
output="$temporary_dir/snapshot.json"
fixture_path="$project_root/tests/fixtures/bin:$PATH"

PATH="$fixture_path" XDG_CACHE_HOME="$temporary_dir/cache" \
    "$project_root/src/boot-story-snapshot" > "$output"

python3 - "$output" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    snapshot = json.load(handle)

assert snapshot["ok"] is True
assert snapshot["system"]["available"] is True
assert snapshot["system"]["totalMs"] == 3_000
assert snapshot["system"]["readyUserspaceMs"] == 1_500
assert isinstance(snapshot["system"]["stages"], list)
assert snapshot["criticalPath"][0]["unit"] == "fixture-critical.service"
assert snapshot["criticalPath"][0]["durationMs"] == 1_000
assert [item["unit"] for item in snapshot["activations"]] == [
    "fixture-critical.service",
    "fixture-parallel.service",
]
assert snapshot["health"] == "attention"
assert snapshot["failedUnitCount"] == 1
assert snapshot["failedUnits"][0]["unit"] == "fixture-failure.service"
assert snapshot["coverage"]["failedUnitsAvailable"] is True
assert snapshot["coverage"]["userSessionAvailable"] is True
PY

test -f "$temporary_dir/cache/boot-story/history.json"
test "$(stat -c '%a' "$temporary_dir/cache/boot-story/history.json")" = "600"

record_output="$temporary_dir/record-output"
PATH="$fixture_path" XDG_CACHE_HOME="$temporary_dir/record-cache" \
    "$project_root/src/boot-story-snapshot" --record-only > "$record_output"
test ! -s "$record_output"
test -f "$temporary_dir/record-cache/boot-story/history.json"

unit_output="$temporary_dir/unit.json"
PATH="$fixture_path" "$project_root/src/boot-story-snapshot" \
    --inspect-unit systemd-journald.service > "$unit_output"

python3 - "$unit_output" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    details = json.load(handle)

assert details["ok"] is True
assert details["unit"] == "systemd-journald.service"
assert details["description"] == "Journal Service"
assert details["activeState"] == "active"
assert details["result"] == "success"
assert details["relationships"]["pulledInBy"]
assert details["relationships"]["bringsIn"]
PY
