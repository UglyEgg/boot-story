// SPDX-License-Identifier: GPL-3.0-or-later
.pragma library

function emptySnapshot() {
    return {
        ok: false,
        health: "unavailable",
        summary: "Waiting for the boot story",
        timestampMs: Date.now(),
        bootAgeMs: 0,
        system: { available: false, totalMs: 0, readyUserspaceMs: 0, stages: [] },
        userSession: { available: false, totalMs: 0, readyUserspaceMs: 0, stages: [] },
        criticalPath: [],
        criticalPathTotal: 0,
        activations: [],
        activationTotal: 0,
        failedUnits: [],
        failedUnitCount: 0,
        comparison: { kind: "baseline", baselineCount: 0, medianMs: 0, deltaMs: 0 },
        recentBoots: [],
        coverage: {
            criticalPathAvailable: false,
            activationsAvailable: false,
            userSessionAvailable: false,
            failedUnitsAvailable: false,
            historyAvailable: false
        }
    };
}

function duration(milliseconds) {
    var value = Math.max(0, Number(milliseconds) || 0);
    if (value < 1)
        return "<1 ms";
    if (value < 1000)
        return Math.round(value) + " ms";
    if (value < 60000)
        return (value / 1000).toFixed(1) + " s";
    var minutes = Math.floor(value / 60000);
    var seconds = Math.round((value % 60000) / 1000);
    return minutes + "m " + seconds + "s";
}

function age(milliseconds) {
    var seconds = Math.max(0, Math.floor((Number(milliseconds) || 0) / 1000));
    var days = Math.floor(seconds / 86400);
    var hours = Math.floor((seconds % 86400) / 3600);
    var minutes = Math.floor((seconds % 3600) / 60);
    if (days > 0)
        return days + "d " + hours + "h";
    if (hours > 0)
        return hours + "h " + minutes + "m";
    return minutes + "m";
}
