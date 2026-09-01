// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../src/qml/Story.js" as Story

TestCase {
    name: "Story"

    function test_formatters() {
        compare(Story.duration(297), "297 ms");
        compare(Story.duration(24863), "24.9 s");
        compare(Story.age(90000000), "1d 1h");
    }

    function test_emptySnapshotMatchesBackendContract() {
        var snapshot = Story.emptySnapshot();
        verify(!snapshot.ok);
        compare(snapshot.failedUnitCount, 0);
        compare(snapshot.criticalPathTotal, 0);
        verify(snapshot.coverage.failedUnitsAvailable === false);
    }
}
