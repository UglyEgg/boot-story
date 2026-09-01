// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: referenceList

    property var references: []
    property string emptyText: ""
    property color accent: Kirigami.Theme.highlightColor

    spacing: 2
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight

    Controls.Label {
        Layout.fillWidth: true
        visible: !referenceList.references || referenceList.references.length === 0
        text: referenceList.emptyText
        opacity: 0.68
        font: Kirigami.Theme.smallFont
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: referenceList.references || []

        delegate: RowLayout {
            id: referenceRow

            required property var modelData
            readonly property string friendlyName: String(modelData.name || modelData.unit || "")
            readonly property string exactName: String(modelData.unit || "")

            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 6
                radius: width / 2
                color: referenceList.accent
                opacity: 0.82
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Controls.Label {
                    Layout.fillWidth: true
                    text: referenceRow.friendlyName
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Controls.Label {
                    Layout.fillWidth: true
                    visible: referenceRow.exactName.length > 0 && referenceRow.exactName !== referenceRow.friendlyName
                    text: referenceRow.exactName
                    opacity: 0.58
                    font.family: "monospace"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }
}
