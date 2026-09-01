// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: section

    property string title: ""
    property string caption: ""
    property string iconName: "dialog-information"
    property color accent: Kirigami.Theme.highlightColor
    default property alias sectionContent: body.data

    function alpha(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }

    implicitHeight: sectionLayout.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight
    radius: 5
    color: alpha(Kirigami.Theme.textColor, 0.035)
    border.width: 1
    border.color: alpha(Kirigami.Theme.textColor, 0.14)

    ColumnLayout {
        id: sectionLayout

        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 4
                color: section.alpha(section.accent, 0.14)
                border.width: 1
                border.color: section.alpha(section.accent, 0.28)

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: section.iconName
                    opacity: 0.82
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Controls.Label {
                    Layout.fillWidth: true
                    text: section.title
                    font.family: Kirigami.Theme.smallFont.family
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Controls.Label {
                    Layout.fillWidth: true
                    visible: section.caption.length > 0
                    text: section.caption
                    opacity: 0.6
                    font: Kirigami.Theme.smallFont
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            Layout.preferredHeight: 1
            color: section.alpha(Kirigami.Theme.textColor, 0.1)
        }

        ColumnLayout {
            id: body

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
        }
    }
}
