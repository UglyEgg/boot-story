// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Story.js" as Story

Controls.AbstractButton {
    id: row

    required property var entry
    required property real maximum
    property color accent: Kirigami.Theme.highlightColor
    property bool diamond: false
    property string detail: ""

    signal inspectionRequested(var selectedEntry)

    function alpha(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }

    implicitHeight: 34
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: qsTr("Inspect %1").arg(entry.name || entry.unit)
    Accessible.description: qsTr("%1 activation").arg(Story.duration(entry.durationMs))
    onClicked: inspectionRequested(entry)

    background: Rectangle {
        radius: 2
        color: row.down ? row.alpha(row.accent, 0.16) : (row.hovered || row.visualFocus ? row.alpha(row.accent, 0.09) : row.alpha(Kirigami.Theme.textColor, 0.045))
        border.width: 1
        border.color: row.visualFocus ? row.accent : row.alpha(row.hovered ? row.accent : Kirigami.Theme.textColor, row.hovered ? 0.46 : 0.08)
    }

    contentItem: RowLayout {
        spacing: 7

        Rectangle {
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: row.diamond ? 0 : 2
            rotation: row.diamond ? 45 : 0
            color: row.accent
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Controls.Label {
                    Layout.fillWidth: true
                    text: row.entry.name || row.entry.unit
                    font.family: Kirigami.Theme.smallFont.family
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Controls.Label {
                    visible: row.detail.length > 0
                    text: row.detail
                    opacity: 0.66
                    font: Kirigami.Theme.smallFont
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 1
                color: row.alpha(Kirigami.Theme.textColor, 0.14)

                Rectangle {
                    width: Math.round(parent.width * Math.max(0.015, Math.min(1, Number(row.entry.durationMs || 0) / Math.max(1, row.maximum))))
                    height: parent.height
                    radius: 1
                    color: row.accent
                }
            }
        }

        Controls.Label {
            Layout.preferredWidth: 55
            text: Story.duration(row.entry.durationMs)
            color: row.accent
            font.family: Kirigami.Theme.smallFont.family
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
        }
    }

    Controls.ToolTip.visible: hovered
    Controls.ToolTip.text: qsTr("Inspect %1").arg(entry.unit || entry.name)

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
}
