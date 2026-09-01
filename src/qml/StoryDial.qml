// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

Item {
    id: dial

    property var stages: []
    property var stageColors: ["#4f8dd6", "#4fc38b", "#d99b3d", "#ab70d6", "#d65c68"]
    property color trackColor: "white"

    readonly property real total: {
        var value = 0;
        for (var index = 0; index < stages.length; index += 1)
            value += Number(stages[index].durationMs || 0);
        return Math.max(1, value);
    }

    onStagesChanged: canvas.requestPaint()
    onStageColorsChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        anchors.fill: parent
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var context = getContext("2d");
            context.reset();
            var size = Math.min(width, height);
            var centerX = Math.round(width / 2);
            var centerY = Math.round(height / 2);
            var radius = Math.round(size * 0.39);
            var start = -Math.PI * 0.75;
            var span = Math.PI * 1.5;
            var gap = 0.035;
            context.lineWidth = Math.round(Math.max(6, size * 0.075));
            context.lineCap = "butt";
            context.strokeStyle = dial.trackColor;
            context.globalAlpha = 0.14;
            context.beginPath();
            context.arc(centerX, centerY, radius, start, start + span);
            context.stroke();
            context.globalAlpha = 1;

            var angle = start;
            for (var index = 0; index < dial.stages.length; index += 1) {
                var part = span * Number(dial.stages[index].durationMs || 0) / dial.total;
                context.strokeStyle = dial.stageColors[index % dial.stageColors.length];
                context.beginPath();
                context.arc(centerX, centerY, radius, angle + gap, angle + Math.max(gap, part - gap));
                context.stroke();
                angle += part;
            }
        }
    }
}
