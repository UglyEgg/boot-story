// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Story.js" as Story

Item {
    id: timeline

    property var stages: []
    property var stageColors: ["#4f8dd6", "#4fc38b", "#d99b3d", "#ab70d6", "#d65c68"]
    property color textColor: "white"
    property int selectedIndex: -1

    readonly property real total: {
        var value = 0;
        for (var index = 0; index < stages.length; index += 1)
            value += Number(stages[index].durationMs || 0);
        return Math.max(1, value);
    }

    function elapsedBefore(index) {
        var value = 0;
        for (var stage = 0; stage < index; stage += 1)
            value += Number(stages[stage].durationMs || 0);
        return value;
    }

    function segmentStart(index, width, gap) {
        var usable = Math.max(0, width - gap * Math.max(0, stages.length - 1));
        return Math.round(usable * elapsedBefore(index) / total) + index * gap;
    }

    function segmentEnd(index, width, gap) {
        var usable = Math.max(0, width - gap * Math.max(0, stages.length - 1));
        var elapsed = elapsedBefore(index) + Number(stages[index].durationMs || 0);
        return Math.round(usable * elapsed / total) + index * gap;
    }

    function compactLabel(label) {
        return String(label) === "Bootloader" ? qsTr("Loader") : String(label);
    }

    onStagesChanged: {
        if (selectedIndex >= stages.length)
            selectedIndex = -1;
    }

    Item {
        id: bar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 18
        readonly property int gap: 2

        Rectangle {
            anchors.fill: parent
            radius: 2
            color: Qt.rgba(timeline.textColor.r, timeline.textColor.g, timeline.textColor.b, 0.12)
        }

        Repeater {
            model: timeline.stages
            delegate: Rectangle {
                required property int index

                x: timeline.segmentStart(index, bar.width, bar.gap)
                width: Math.max(2, timeline.segmentEnd(index, bar.width, bar.gap) - x)
                height: bar.height
                radius: 2
                color: timeline.stageColors[index % timeline.stageColors.length]
            }
        }
    }

    Item {
        id: phaseControls

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: bar.bottom
        anchors.topMargin: 7
        anchors.bottom: parent.bottom

        Repeater {
            model: timeline.stages
            delegate: Controls.AbstractButton {
                id: phaseButton

                required property var modelData
                required property int index

                x: timeline.segmentStart(index, phaseControls.width, bar.gap)
                width: Math.max(2, timeline.segmentEnd(index, phaseControls.width, bar.gap) - x)
                height: phaseControls.height
                hoverEnabled: true
                focusPolicy: Qt.TabFocus
                text: qsTr("%1 phase, %2").arg(modelData.label).arg(Story.duration(modelData.durationMs))
                Accessible.name: text
                onClicked: timeline.selectedIndex = timeline.selectedIndex === index ? -1 : index

                background: Rectangle {
                    radius: 2
                    color: timeline.selectedIndex === index
                           ? Qt.rgba(timeline.stageColors[index % timeline.stageColors.length].r,
                                     timeline.stageColors[index % timeline.stageColors.length].g,
                                     timeline.stageColors[index % timeline.stageColors.length].b,
                                     0.13)
                           : Qt.rgba(timeline.textColor.r, timeline.textColor.g, timeline.textColor.b,
                                     phaseButton.hovered ? 0.075 : 0.035)
                    border.width: 1
                    border.color: timeline.selectedIndex === index || parent.activeFocus
                                  ? timeline.stageColors[index % timeline.stageColors.length]
                                  : Qt.rgba(timeline.textColor.r, timeline.textColor.g, timeline.textColor.b, 0.12)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 3
                        color: timeline.stageColors[index % timeline.stageColors.length]
                    }
                }

                contentItem: ColumnLayout {
                    spacing: 0

                    Controls.Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        text: timeline.compactLabel(modelData.label)
                        color: timeline.textColor
                        opacity: 0.86
                        font.family: Kirigami.Theme.smallFont.family
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                    Controls.Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        text: Story.duration(modelData.durationMs)
                        color: timeline.textColor
                        font.family: Kirigami.Theme.smallFont.family
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                Controls.ToolTip.visible: hovered
                Controls.ToolTip.text: qsTr("Select to explain the %1 phase").arg(modelData.label)
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }
    }
}
