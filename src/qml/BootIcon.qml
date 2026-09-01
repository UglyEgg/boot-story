// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

Item {
    id: icon

    property color color: "white"
    property color accentColor: color

    onColorChanged: canvas.requestPaint()
    onAccentColorChanged: canvas.requestPaint()

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
            var centerX = width / 2;
            var centerY = height / 2;
            var line = Math.max(2, size * 0.075);
            var startAngle = Math.PI * 0.75;
            var sweepAngle = Math.PI * 1.5;
            context.lineWidth = line;
            context.lineCap = "round";
            context.strokeStyle = icon.color;
            context.globalAlpha = 0.48;
            for (var ring = 0; ring < 3; ring += 1) {
                context.beginPath();
                context.arc(centerX, centerY, size * (0.18 + ring * 0.12), startAngle, startAngle + sweepAngle);
                context.stroke();
            }
            context.globalAlpha = 1;
            context.strokeStyle = icon.accentColor;
            context.beginPath();
            context.arc(centerX, centerY, size * 0.42, startAngle, startAngle + sweepAngle);
            context.stroke();

            var needleAngle = -Math.PI * 0.25;
            var directionX = Math.cos(needleAngle);
            var directionY = Math.sin(needleAngle);
            var perpendicularX = -directionY;
            var perpendicularY = directionX;
            var needleLength = size * 0.31;
            var needleHalfWidth = size * 0.075;
            context.fillStyle = icon.accentColor;
            context.beginPath();
            context.moveTo(centerX + perpendicularX * needleHalfWidth, centerY + perpendicularY * needleHalfWidth);
            context.lineTo(centerX + directionX * needleLength, centerY + directionY * needleLength);
            context.lineTo(centerX - perpendicularX * needleHalfWidth, centerY - perpendicularY * needleHalfWidth);
            context.closePath();
            context.fill();

            context.beginPath();
            context.arc(centerX, centerY, size * 0.075, 0, Math.PI * 2);
            context.fill();
        }
    }
}
