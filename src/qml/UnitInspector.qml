// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Story.js" as Story

Flickable {
    id: inspector

    property var entry: ({})
    property string contextKind: ""
    property var details: ({})
    property bool busy: false
    property string errorMessage: ""
    property bool showEvidence: false

    signal closeRequested

    readonly property var relationships: details.relationships || ({})
    readonly property real scrollGutter: verticalScrollBar.implicitWidth + Kirigami.Units.smallSpacing
    readonly property color stateColor: {
        if (String(details.activeState) === "failed")
            return Kirigami.Theme.negativeTextColor;
        if (String(details.activeState) === "active")
            return Kirigami.Theme.positiveTextColor;
        return Kirigami.Theme.neutralTextColor;
    }

    contentWidth: width
    contentHeight: content.height + Kirigami.Units.largeSpacing * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Controls.ScrollBar.vertical: Controls.ScrollBar {
        id: verticalScrollBar
    }

    onEntryChanged: showEvidence = false

    function alpha(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }

    function bootContext() {
        var name = String(entry.name || details.name || entry.unit || qsTr("This unit"));
        var duration = Story.duration(Number(entry.durationMs || 0));
        if (contextKind === "critical") {
            return qsTr("%1 spent %2 activating on the dependency chain that led to the graphical desktop. Because boot work can overlap, that does not mean removing it would save the full %2.").arg(name).arg(duration);
        }
        if (contextKind === "failure") {
            return qsTr("systemd recorded %1 as failed before graphical.target became ready. The state shown above is current and may have changed since boot.").arg(name);
        }
        return qsTr("systemd measured %1 while %2 activated. It may have run beside other work, so this is a useful clue—not proof that it delayed the desktop by %1.").arg(duration).arg(name);
    }

    ColumnLayout {
        id: content

        x: Kirigami.Units.largeSpacing
        y: Kirigami.Units.largeSpacing
        width: Math.max(0, inspector.width - Kirigami.Units.largeSpacing * 2 - inspector.scrollGutter)
        height: implicitHeight
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 1
                    text: entry.name || details.name || qsTr("Unit details")
                    elide: Text.ElideRight
                }
                Controls.Label {
                    Layout.fillWidth: true
                    text: entry.unit || details.unit || ""
                    opacity: 0.68
                    font: Kirigami.Theme.smallFont
                    elide: Text.ElideMiddle
                }
            }

            Controls.ToolButton {
                icon.name: "window-close"
                display: Controls.AbstractButton.IconOnly
                Accessible.name: qsTr("Close unit details")
                onClicked: inspector.closeRequested()
                Controls.ToolTip.visible: hovered
                Controls.ToolTip.text: qsTr("Close")
            }
        }

        Controls.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: inspector.busy
            visible: running
        }

        Controls.Label {
            visible: inspector.busy
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Reading this unit…")
            opacity: 0.72
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: inspector.errorMessage.length > 0
            type: Kirigami.MessageType.Error
            text: inspector.errorMessage
        }

        ColumnLayout {
            visible: !inspector.busy && inspector.errorMessage.length === 0 && Boolean(details.ok)
            Layout.fillWidth: true
            Layout.minimumHeight: implicitHeight
            spacing: Kirigami.Units.largeSpacing

            Controls.Label {
                Layout.fillWidth: true
                visible: String(details.description || "").length > 0
                text: details.description || ""
                wrapMode: Text.WordWrap
                font.weight: Font.DemiBold
            }

            Controls.Label {
                Layout.fillWidth: true
                text: qsTr("CURRENT UNIT STATE")
                opacity: 0.66
                font.family: Kirigami.Theme.smallFont.family
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.weight: Font.DemiBold
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.preferredWidth: activeStateLabel.implicitWidth + 18
                    Layout.preferredHeight: 27
                    radius: 3
                    color: inspector.alpha(inspector.stateColor, 0.13)
                    border.width: 1
                    border.color: inspector.alpha(inspector.stateColor, 0.48)

                    Controls.Label {
                        id: activeStateLabel
                        anchors.centerIn: parent
                        text: [details.activeState || qsTr("unknown"), details.subState || ""].filter(function (value) {
                            return String(value).length > 0;
                        }).join(" · ")
                        color: inspector.stateColor
                        font.family: Kirigami.Theme.smallFont.family
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    visible: String(details.result || "").length > 0
                    Layout.preferredWidth: currentResultLabel.implicitWidth + 18
                    Layout.preferredHeight: 27
                    radius: 3
                    color: inspector.alpha(Kirigami.Theme.textColor, 0.05)
                    border.width: 1
                    border.color: inspector.alpha(Kirigami.Theme.textColor, 0.18)

                    Controls.Label {
                        id: currentResultLabel
                        anchors.centerIn: parent
                        text: qsTr("result: %1").arg(details.result || qsTr("unknown"))
                        opacity: 0.82
                        font: Kirigami.Theme.smallFont
                    }
                }

                Rectangle {
                    visible: String(details.unitFileState || "").length > 0
                    Layout.preferredWidth: fileStateLabel.implicitWidth + 18
                    Layout.preferredHeight: 27
                    radius: 3
                    color: inspector.alpha(Kirigami.Theme.textColor, 0.05)
                    border.width: 1
                    border.color: inspector.alpha(Kirigami.Theme.textColor, 0.18)

                    Controls.Label {
                        id: fileStateLabel
                        anchors.centerIn: parent
                        text: details.unitFileState || ""
                        opacity: 0.82
                        font: Kirigami.Theme.smallFont
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Controls.Label {
                    visible: Number(entry.durationMs || 0) > 0
                    text: Story.duration(Number(entry.durationMs || 0))
                    color: Kirigami.Theme.highlightColor
                    font.weight: Font.DemiBold
                }
            }

            InspectorSection {
                Layout.fillWidth: true
                title: qsTr("Boot measurement")
                iconName: "chronometer"
                accent: Kirigami.Theme.highlightColor
                color: inspector.alpha(accent, 0.065)
                border.color: inspector.alpha(accent, 0.34)

                Controls.Label {
                    Layout.fillWidth: true
                    text: inspector.bootContext()
                    wrapMode: Text.WordWrap
                }
            }

            InspectorSection {
                Layout.fillWidth: true
                title: qsTr("Who asks for it now")
                caption: qsTr("Current loaded relationships, not proof of boot causality")
                iconName: "go-next"
                accent: Kirigami.Theme.positiveTextColor

                InspectorReferenceList {
                    Layout.fillWidth: true
                    references: inspector.relationships.pulledInBy || []
                    emptyText: qsTr("No loaded unit directly requires or wants this unit.")
                    accent: Kirigami.Theme.positiveTextColor
                }
            }

            InspectorSection {
                Layout.fillWidth: true
                title: qsTr("What it asks for now")
                caption: qsTr("Current direct requirements and wants")
                iconName: "system-run"
                accent: Kirigami.Theme.neutralTextColor

                InspectorReferenceList {
                    Layout.fillWidth: true
                    references: inspector.relationships.bringsIn || []
                    emptyText: qsTr("No direct required or wanted units were reported.")
                    accent: Kirigami.Theme.neutralTextColor
                }
            }

            Controls.Button {
                Layout.alignment: Qt.AlignLeft
                text: inspector.showEvidence ? qsTr("Hide how we know") : qsTr("Show how we know")
                icon.name: inspector.showEvidence ? "go-up" : "go-down"
                checkable: true
                checked: inspector.showEvidence
                onToggled: inspector.showEvidence = checked
            }

            ColumnLayout {
                visible: inspector.showEvidence
                Layout.fillWidth: true
                Layout.minimumHeight: implicitHeight
                spacing: Kirigami.Units.largeSpacing

                InspectorSection {
                    Layout.fillWidth: true
                    title: qsTr("Measured during this boot")
                    caption: qsTr("Boot-scoped timing evidence")
                    iconName: "preferences-system-time"
                    accent: Kirigami.Theme.highlightColor

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            visible: Number(inspector.entry.activatedMs || 0) > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            radius: 3
                            color: inspector.alpha(Kirigami.Theme.textColor, 0.045)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: 0

                                Controls.Label {
                                    text: qsTr("STARTED AT")
                                    opacity: 0.58
                                    font: Kirigami.Theme.smallFont
                                }
                                Controls.Label {
                                    text: Story.duration(Number(inspector.entry.activatedMs || 0))
                                    color: Kirigami.Theme.highlightColor
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            radius: 3
                            color: inspector.alpha(Kirigami.Theme.textColor, 0.045)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: 0

                                Controls.Label {
                                    text: qsTr("ACTIVATION")
                                    opacity: 0.58
                                    font: Kirigami.Theme.smallFont
                                }
                                Controls.Label {
                                    text: Story.duration(Number(inspector.entry.durationMs || 0))
                                    color: Kirigami.Theme.highlightColor
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                    }

                    Controls.Label {
                        visible: Number(inspector.entry.activatedMs || 0) > 0
                        Layout.fillWidth: true
                        text: qsTr("Started at is measured from the beginning of system userspace, not from power-on.")
                        opacity: 0.6
                        font: Kirigami.Theme.smallFont
                        wrapMode: Text.WordWrap
                    }
                }

                InspectorSection {
                    Layout.fillWidth: true
                    title: qsTr("Current ordering constraints")
                    caption: qsTr("What the loaded configuration places before this unit")
                    iconName: "view-list-details"
                    accent: Kirigami.Theme.linkColor

                    InspectorReferenceList {
                        Layout.fillWidth: true
                        references: inspector.relationships.orderedAfter || []
                        emptyText: qsTr("No relevant “after” relationships were reported.")
                        accent: Kirigami.Theme.linkColor
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        text: qsTr("“After” controls sequence only; it does not cause a unit to start.")
                        opacity: 0.6
                        font: Kirigami.Theme.smallFont
                        wrapMode: Text.WordWrap
                    }
                }

                InspectorSection {
                    visible: String(details.fragmentPath || "").length > 0
                    Layout.fillWidth: true
                    title: qsTr("Unit file")
                    caption: qsTr("Definition loaded now; it may differ from boot")
                    iconName: "document-properties"
                    accent: Kirigami.Theme.textColor

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: unitPath.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: 3
                        color: inspector.alpha(Kirigami.Theme.textColor, 0.055)

                        TextEdit {
                            id: unitPath
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Kirigami.Units.smallSpacing
                            anchors.rightMargin: Kirigami.Units.smallSpacing
                            text: details.fragmentPath || ""
                            wrapMode: Text.WrapAnywhere
                            readOnly: true
                            selectByMouse: true
                            color: Kirigami.Theme.textColor
                            selectionColor: Kirigami.Theme.highlightColor
                            selectedTextColor: Kirigami.Theme.highlightedTextColor
                            font.family: "monospace"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }
            }
        }
    }
}
