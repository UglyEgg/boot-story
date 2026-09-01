# SPDX-License-Identifier: GPL-3.0-or-later

import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch


HELPER_PATH = Path(__file__).parents[1] / "src" / "boot-story-snapshot"
SPEC = importlib.util.spec_from_loader(
    "boot_story_snapshot",
    SourceFileLoader("boot_story_snapshot", str(HELPER_PATH)),
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SnapshotTests(unittest.TestCase):
    def test_duration_parser_handles_compound_units(self):
        self.assertEqual(MODULE.duration_to_ms("1min 2.5s"), 62_500)
        self.assertAlmostEqual(MODULE.duration_to_ms("704us"), 0.704)

    def test_parse_startup_time_builds_stages_and_target(self):
        text = (
            "Startup finished in 5.4s (firmware) + 2.0s (loader) + 1.5s (kernel) "
            "+ 4.0s (initrd) + 10.0s (userspace) = 22.9s\n"
            "graphical.target reached after 9.8s in userspace.\n"
        )
        parsed = MODULE.parse_startup_time(text)
        self.assertEqual(parsed["totalMs"], 22_900)
        self.assertEqual(len(parsed["stages"]), 5)
        self.assertEqual(parsed["readyUserspaceMs"], 9_800)

    def test_startup_and_critical_chain_accept_compound_durations(self):
        parsed = MODULE.parse_startup_time(
            "Startup finished in 1.0s (kernel) + 1min 2.5s (userspace) = 1min 3.5s\n"
            "graphical.target reached after 1min 2.5s in userspace.\n"
        )
        self.assertEqual(parsed["totalMs"], 63_500)
        self.assertEqual(parsed["stages"][-1]["durationMs"], 62_500)
        self.assertEqual(parsed["readyUserspaceMs"], 62_500)

        critical = MODULE.parse_critical_chain(
            "graphical.target @1min 2.5s\n└─slow.service @1min 1s +1min 0.5s\n"
        )
        self.assertEqual(critical[0]["activatedMs"], 61_000)
        self.assertEqual(critical[0]["durationMs"], 60_500)

    def test_parse_user_time_without_equals_uses_stage_sum(self):
        parsed = MODULE.parse_startup_time(
            "Startup finished in 297ms (userspace)\ndefault.target reached after 297ms in userspace.\n"
        )
        self.assertEqual(parsed["totalMs"], 297)
        self.assertEqual(parsed["readyTarget"], "default.target")

    def test_critical_chain_strips_tree_prefix_and_sorts(self):
        text = "graphical.target @10s\n└─slow.service @2s +8s\n  └─fast.service @1s +200ms\n"
        parsed = MODULE.parse_critical_chain(text)
        self.assertEqual(parsed[0]["unit"], "slow.service")
        self.assertEqual(parsed[0]["durationMs"], 8_000)

    def test_friendly_names_cover_relationship_unit_types(self):
        self.assertEqual(MODULE.friendly_unit("system.slice"), "System")
        self.assertEqual(MODULE.friendly_unit("fstrim.timer"), "Fstrim")

    def test_blame_filters_devices_and_implausibly_late_work(self):
        text = "2min later.service\n8.2s online.service\n5.4s dev-sda.device\n"
        parsed = MODULE.parse_blame(text, 12_000, {"online.service"})
        self.assertEqual([entry["unit"] for entry in parsed], ["online.service"])
        self.assertTrue(parsed[0]["onCriticalPath"])

    def test_boot_failures_are_bounded_by_desktop_ready_time(self):
        events = [
            {
                "__MONOTONIC_TIMESTAMP": "9000000",
                "UNIT": "early-failure.service",
                "MESSAGE_ID": MODULE.UNIT_FAILED_MESSAGE_IDS[0],
            },
            {
                "__MONOTONIC_TIMESTAMP": "9001000",
                "UNIT": "early-failure.service",
                "MESSAGE_ID": MODULE.UNIT_FAILED_MESSAGE_IDS[1],
            },
            {
                "__MONOTONIC_TIMESTAMP": "15000000",
                "UNIT": "later-crash.service",
                "MESSAGE_ID": MODULE.UNIT_FAILED_MESSAGE_IDS[1],
            },
        ]
        text = "\n".join(json.dumps(event) for event in events)

        self.assertEqual(MODULE.parse_boot_failures(text, 10_000_000), ["early-failure.service"])

    def test_boot_failures_ignore_malformed_or_unsafe_journal_entries(self):
        text = "\n".join([
            "not json",
            json.dumps({"__MONOTONIC_TIMESTAMP": "1000", "UNIT": "../unsafe.service"}),
            json.dumps({"__MONOTONIC_TIMESTAMP": "invalid", "UNIT": "broken.service"}),
        ])

        self.assertEqual(MODULE.parse_boot_failures(text, 10_000), [])

    def test_incremental_command_reader_enforces_output_limits(self):
        lines, error = MODULE.run_bounded_lines(
            ["/usr/bin/yes", "event"],
            time.monotonic() + 1.0,
            maximum_bytes=1024,
            maximum_lines=32,
        )
        self.assertTrue(lines)
        self.assertIn("safety limit", error)

    def test_comparison_uses_local_median(self):
        previous = [{"totalMs": 20_000}, {"totalMs": 22_000}, {"totalMs": 24_000}]
        self.assertEqual(MODULE.comparison_for(18_000, previous)["kind"], "faster")
        self.assertEqual(MODULE.comparison_for(22_500, previous)["kind"], "steady")
        self.assertEqual(MODULE.comparison_for(28_000, previous)["kind"], "slower")

    def test_history_is_private_and_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "history.json"
            entries = [
                {
                    "bootId": str(index),
                    "timestampMs": 1_700_000_000_000 + index,
                    "totalMs": 10_000,
                    "readyUserspaceMs": 8_000,
                }
                for index in range(30)
            ]
            MODULE.save_history(path, entries)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            loaded, warning = MODULE.load_history(path)
            self.assertEqual(warning, "")
            self.assertEqual(len(loaded), MODULE.MAX_HISTORY)
            self.assertFalse(list(path.parent.glob(".history-*.tmp")))

    def test_history_lock_contention_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "boot-story" / "history.json"
            original_timeout = MODULE.HISTORY_LOCK_TIMEOUT_SECONDS
            MODULE.HISTORY_LOCK_TIMEOUT_SECONDS = 0.02
            try:
                with MODULE.history_lock(path):
                    started = time.monotonic()
                    with self.assertRaisesRegex(OSError, "history file is busy"):
                        with MODULE.history_lock(path):
                            pass
                    self.assertLess(time.monotonic() - started, 0.2)
            finally:
                MODULE.HISTORY_LOCK_TIMEOUT_SECONDS = original_timeout

    def test_update_history_replaces_current_boot(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "history.json"
            system = {"totalMs": 20_000, "readyUserspaceMs": 10_000}
            MODULE.update_history(system, path, 1_000.0)
            MODULE.update_history(system, path, 2_000.0)
            loaded, warning = MODULE.load_history(path)
            self.assertEqual(warning, "")
            self.assertEqual(len(loaded), 1)

    def test_history_rejects_oversized_and_future_schema_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "history.json"
            path.write_text("x" * (MODULE.MAX_HISTORY_BYTES + 1), encoding="utf-8")
            self.assertIn("safety limit", MODULE.load_history(path)[1])

            path.write_text(json.dumps({"version": 99, "boots": []}), encoding="utf-8")
            self.assertIn("schema version", MODULE.load_history(path)[1])

    def test_empty_or_relative_xdg_cache_home_uses_home_fallback(self):
        with patch.dict(os.environ, {"XDG_CACHE_HOME": ""}, clear=False):
            self.assertEqual(MODULE.history_path(), Path.home() / ".cache/boot-story/history.json")
        with patch.dict(os.environ, {"XDG_CACHE_HOME": "relative-cache"}, clear=False):
            self.assertEqual(MODULE.history_path(), Path.home() / ".cache/boot-story/history.json")

    def test_graphical_ready_info_uses_explicit_target(self):
        with patch.object(MODULE, "run_command", side_effect=[
            ("ActiveEnterTimestamp=Tue 2026-09-01 10:00:00 CDT\nActiveEnterTimestampMonotonic=15000000\n", ""),
            ("UserspaceTimestampMonotonic=5000000\n", ""),
        ]) as command:
            ready, error = MODULE.graphical_ready_info()

        self.assertEqual(error, "")
        self.assertEqual(ready["target"], "graphical.target")
        self.assertEqual(ready["userspaceMs"], 10_000)
        self.assertEqual(command.call_args_list[0].args[0][-2:], ["--", "graphical.target"])

    def test_optional_probe_and_history_failures_are_explicitly_degraded(self):
        def fake_command(arguments, *_args, **_kwargs):
            if arguments[:2] == ["systemd-analyze", "time"]:
                return (
                    "Startup finished in 1s (kernel) + 10s (userspace) = 11s\n"
                    "graphical.target reached after 9s in userspace.\n",
                    "",
                )
            return "", "probe unavailable"

        with (
            patch.object(MODULE, "run_command", side_effect=fake_command),
            patch.object(MODULE, "collect_failed_units", return_value=([], {}, "journal denied")),
            patch.object(MODULE, "update_history", side_effect=OSError("read-only cache")),
        ):
            snapshot = MODULE.collect(Path("/unused/history.json"), now=1_000.0)

        self.assertTrue(snapshot["ok"])
        self.assertEqual(snapshot["health"], "unknown")
        self.assertFalse(snapshot["coverage"]["criticalPathAvailable"])
        self.assertFalse(snapshot["coverage"]["failedUnitsAvailable"])
        self.assertFalse(snapshot["coverage"]["historyAvailable"])
        self.assertIn("read-only cache", snapshot["coverage"]["historyError"])

    def test_inspect_unit_explains_relationships_and_status_evidence(self):
        show_output = "\n".join([
            "Id=demo.service",
            "Description=Demonstration service",
            "LoadState=loaded",
            "ActiveState=active",
            "SubState=running",
            "UnitFileState=enabled",
            "FragmentPath=/usr/lib/systemd/system/demo.service",
            "Result=success",
            "WantedBy=multi-user.target",
            "RequiredBy=graphical.target",
            "Requires=network.target system.slice",
            "Wants=helper.service",
            "After=network.target system.slice",
        ])
        with patch.object(MODULE, "run_command", return_value=(show_output, "")) as command:
            details = MODULE.inspect_unit("demo.service")

        self.assertTrue(details["ok"])
        self.assertEqual(details["description"], "Demonstration service")
        self.assertEqual(details["result"], "success")
        self.assertEqual(
            [entry["unit"] for entry in details["relationships"]["pulledInBy"]],
            ["graphical.target", "multi-user.target"],
        )
        self.assertEqual(
            [entry["unit"] for entry in details["relationships"]["bringsIn"]],
            ["network.target", "system.slice", "helper.service"],
        )
        self.assertEqual(command.call_count, 1)
        self.assertEqual(command.call_args_list[0].args[0][-2:], ["--", "demo.service"])

    def test_inspect_unit_rejects_unsafe_names_before_running_commands(self):
        with patch.object(MODULE, "run_command") as command:
            details = MODULE.inspect_unit("../demo.service")

        self.assertFalse(details["ok"])
        self.assertIn("not safe", details["error"])
        command.assert_not_called()


if __name__ == "__main__":
    unittest.main()
