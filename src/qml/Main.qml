// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Story.js" as Story

Kirigami.ApplicationWindow {
    id: window

    width: 940
    height: 680
    minimumWidth: 720
    minimumHeight: 560
    visible: true
    title: qsTr("Boot Story")
    Kirigami.Theme.colorSet: Kirigami.Theme.Window

    property var snapshot: bootBackend.snapshot && bootBackend.snapshot.ok ? bootBackend.snapshot : Story.emptySnapshot()
    readonly property bool ready: Boolean(snapshot.ok)
    readonly property var systemBoot: snapshot.system || ({
            stages: [],
            totalMs: 0
        })
    readonly property var userSession: snapshot.userSession || ({
            available: false,
            totalMs: 0
        })
    readonly property var criticalPath: snapshot.criticalPath || []
    readonly property var activations: snapshot.activations || []
    readonly property var failedUnits: snapshot.failedUnits || []
    readonly property var coverage: snapshot.coverage || ({})
    readonly property var comparison: snapshot.comparison || ({
            kind: "baseline",
            baselineCount: 0
        })
    readonly property var recentBoots: snapshot.recentBoots || []
    property var inspectedEntry: ({})
    property string inspectedContext: ""
    property double currentTimeMs: Date.now()
    readonly property color healthColor: {
        if (bootBackend.snapshotStale)
            return Kirigami.Theme.neutralTextColor;
        switch (String(snapshot.health || "baseline")) {
        case "attention":
            return Kirigami.Theme.negativeTextColor;
        case "slower":
            return Kirigami.Theme.neutralTextColor;
        case "faster":
            return Kirigami.Theme.positiveTextColor;
        case "steady":
            return Kirigami.Theme.positiveTextColor;
        case "unknown":
            return Kirigami.Theme.neutralTextColor;
        default:
            return Kirigami.Theme.highlightColor;
        }
    }
    readonly property color criticalPathColor: Kirigami.Theme.highlightColor
    readonly property var stageColorMap: ({
            firmware: Kirigami.Theme.highlightColor,
            loader: Kirigami.Theme.positiveTextColor,
            kernel: Kirigami.Theme.neutralTextColor,
            initrd: Kirigami.Theme.linkColor,
            userspace: Kirigami.Theme.positiveTextColor
        })
    readonly property var stageColors: (systemBoot.stages || []).map(function (stage) {
        return window.stageColorMap[String(stage.key)] || Kirigami.Theme.highlightColor;
    })
    readonly property real maximumCritical: maximumDuration(criticalPath)
    readonly property real maximumActivation: maximumDuration(activations)
    readonly property real maximumHistory: maximumTotal(recentBoots)
    readonly property string statusText: {
        if (bootBackend.snapshotStale)
            return qsTr("Stale");
        switch (String(snapshot.health || "baseline")) {
        case "attention":
            return qsTr("Attention");
        case "slower":
            return qsTr("Slower");
        case "faster":
            return qsTr("Faster");
        case "steady":
            return qsTr("Typical");
        case "unknown":
            return qsTr("Incomplete");
        default:
            return qsTr("Baseline");
        }
    }
    readonly property real currentBootAgeMs: Number(snapshot.bootAgeMs || 0) + Math.max(0, currentTimeMs - Number(snapshot.timestampMs || currentTimeMs))

    Timer {
        interval: 60000
        running: window.visible
        repeat: true
        onTriggered: window.currentTimeMs = Date.now()
    }

    function maximumDuration(entries) {
        var result = 1;
        for (var index = 0; index < entries.length; index += 1)
            result = Math.max(result, Number(entries[index].durationMs || 0));
        return result;
    }

    function maximumTotal(entries) {
        var result = 1;
        for (var index = 0; index < entries.length; index += 1)
            result = Math.max(result, Number(entries[index].totalMs || 0));
        return result;
    }

    function evidenceWarning() {
        var missing = [];
        if (coverage.criticalPathAvailable === false)
            missing.push(qsTr("critical path"));
        if (coverage.activationsAvailable === false)
            missing.push(qsTr("long activations"));
        if (coverage.userSessionAvailable === false)
            missing.push(qsTr("user-session timing"));
        if (coverage.failedUnitsAvailable === false)
            missing.push(qsTr("startup failures"));
        if (coverage.historyAvailable === false)
            missing.push(qsTr("history"));
        return missing.length > 0
            ? qsTr("Some evidence is unavailable: %1. Available measurements remain visible.").arg(missing.join(", "))
            : "";
    }

    function alpha(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }

    function narrative() {
        if (!ready)
            return qsTr("Reading the current boot from systemd…");
        if (Number(snapshot.failedUnitCount || 0) > 0)
            return coverage.failedUnitsAvailable === false
                ? qsTr("At least %1 system units failed while the graphical desktop was starting; the failure check was incomplete.").arg(snapshot.failedUnitCount)
                : qsTr("%1 system units failed while the graphical desktop was starting.").arg(snapshot.failedUnitCount);
        if (coverage.failedUnitsAvailable === false)
            return qsTr("Boot timing is available, but systemd's startup-failure evidence could not be read.");
        if (coverage.criticalPathAvailable === false)
            return qsTr("No failure was reported, but the graphical critical path could not be read.");
        if (criticalPath.length > 0)
            return qsTr("%1 was the largest measured activation on the critical path at %2.").arg(criticalPath[0].name).arg(Story.duration(criticalPath[0].durationMs));
        return qsTr("The critical dependency chain was not available on this system.");
    }

    function phaseExplanation(key) {
        switch (String(key)) {
        case "firmware":
            return qsTr("The computer's firmware initialized hardware and prepared it for the operating system.");
        case "loader":
            return qsTr("The bootloader selected Linux, loaded the kernel and initrd, then handed over control.");
        case "kernel":
            return qsTr("Linux initialized its core subsystems and hardware support before starting early userspace.");
        case "initrd":
            return qsTr("The temporary early-userspace environment found and mounted the real root filesystem.");
        case "userspace":
            return qsTr("systemd started system units until the graphical desktop target became ready. Units overlap, so their individual times do not add up to this phase duration.");
        default:
            return qsTr("This phase is part of the path from power-on to a ready desktop.");
        }
    }

    function openUnitInspector(entry, contextKind) {
        if (!entry || !entry.unit)
            return;
        inspectedEntry = entry;
        inspectedContext = contextKind;
        unitDrawer.open();
        bootBackend.inspectUnit(String(entry.unit));
    }

    Controls.Drawer {
        id: unitDrawer

        edge: Qt.RightEdge
        width: Math.min(570, window.width * 0.74)
        height: window.height
        modal: true
        dim: true
        closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
        onClosed: {
            bootBackend.clearUnitDetails();
            window.inspectedEntry = ({});
            window.inspectedContext = "";
        }

        contentItem: Loader {
            active: unitDrawer.visible

            sourceComponent: UnitInspector {
                entry: window.inspectedEntry
                contextKind: window.inspectedContext
                details: bootBackend.unitDetails
                busy: bootBackend.unitDetailsBusy
                errorMessage: bootBackend.unitDetailsError
                onCloseRequested: unitDrawer.close()
            }
        }
    }

    pageStack.initialPage: Kirigami.Page {
        id: page
        title: qsTr("Boot Story")

        actions: [
            Kirigami.Action {
                text: qsTr("Refresh")
                icon.name: "view-refresh"
                displayHint: Kirigami.DisplayHint.IconOnly | Kirigami.DisplayHint.KeepVisible
                enabled: !bootBackend.busy
                onTriggered: bootBackend.refresh()
            },
            Kirigami.Action {
                text: qsTr("Settings")
                icon.name: "configure"
                displayHint: Kirigami.DisplayHint.IconOnly | Kirigami.DisplayHint.KeepVisible
                onTriggered: settingsDialog.open()
            }
        ]

        Kirigami.InlineMessage {
            id: errorMessage
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            visible: bootBackend.errorMessage.length > 0
            type: Kirigami.MessageType.Error
            text: bootBackend.snapshotStale
                ? qsTr("%1 The previous snapshot remains visible and is now marked stale.").arg(bootBackend.errorMessage)
                : bootBackend.errorMessage
            showCloseButton: true
            z: 2
        }

        Controls.Dialog {
            id: settingsDialog

            parent: Controls.Overlay.overlay
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            width: Math.min(460, parent.width - Kirigami.Units.gridUnit * 3)
            modal: true
            title: qsTr("Boot Story Settings")
            onOpened: bootBackend.refreshHistoryCollectionStatus()

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.largeSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            Layout.fillWidth: true
                            text: qsTr("Automatic history collection")
                            font.weight: Font.DemiBold
                        }
                        Controls.Label {
                            Layout.fillWidth: true
                            text: qsTr("Record one boot snapshot shortly after graphical login, then exit. Boot Story never stays running in the background.")
                            color: Kirigami.Theme.textColor
                            opacity: 0.72
                            wrapMode: Text.WordWrap
                        }
                    }

                    Controls.BusyIndicator {
                        running: bootBackend.historyCollectionBusy
                        visible: running
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                    }

                    Controls.Switch {
                        id: historyCollectionSwitch
                        Accessible.name: qsTr("Automatic history collection")
                        checked: bootBackend.historyCollectionEnabled
                        enabled: bootBackend.historyCollectionAvailable && !bootBackend.historyCollectionBusy
                        onClicked: bootBackend.setHistoryCollectionEnabled(checked)
                    }
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: bootBackend.historyCollectionError.length > 0
                    type: Kirigami.MessageType.Error
                    text: bootBackend.historyCollectionError
                }

                Controls.Label {
                    Layout.fillWidth: true
                    text: bootBackend.historyCollectionBusy
                        ? qsTr("Reading the automatic-history setting…")
                        : (!bootBackend.historyCollectionAvailable
                            ? qsTr("Unavailable · the setting could not be confirmed")
                            : (bootBackend.historyCollectionEnabled
                                ? qsTr("Enabled · this login is scheduled and future logins will be recorded")
                                : qsTr("Disabled · existing history is kept")))
                    color: bootBackend.historyCollectionEnabled ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
                    opacity: bootBackend.historyCollectionEnabled ? 1 : 0.72
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        Flickable {
            anchors.fill: parent
            anchors.topMargin: errorMessage.visible ? errorMessage.height + Kirigami.Units.smallSpacing : 0
            contentWidth: width
            contentHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: content
                width: parent.width
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    Layout.preferredHeight: 66
                    spacing: Kirigami.Units.largeSpacing

                    BootIcon {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46
                        color: Kirigami.Theme.textColor
                        accentColor: window.healthColor
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Kirigami.Heading {
                            Layout.fillWidth: true
                            level: 1
                            text: window.ready ? qsTr("Ready in %1").arg(Story.duration(window.systemBoot.totalMs)) : qsTr("Reading this boot…")
                            elide: Text.ElideRight
                        }
                        Controls.Label {
                            Layout.fillWidth: true
                            text: window.ready ? String(window.snapshot.summary || "") : qsTr("Firmware, Linux, services, and Plasma")
                            opacity: 0.78
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        visible: window.ready
                        Layout.preferredWidth: statusLabel.implicitWidth + 22
                        Layout.preferredHeight: 28
                        radius: 4
                        color: window.alpha(window.healthColor, 0.14)
                        border.width: 1
                        border.color: window.alpha(window.healthColor, 0.52)
                        Controls.Label {
                            id: statusLabel
                            anchors.centerIn: parent
                            text: window.statusText.toUpperCase()
                            color: window.healthColor
                            font.family: Kirigami.Theme.smallFont.family
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            font.weight: Font.DemiBold
                        }
                    }

                    Controls.BusyIndicator {
                        running: bootBackend.busy
                        visible: running
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                    }
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    visible: window.ready && window.evidenceWarning().length > 0
                    type: Kirigami.MessageType.Warning
                    text: window.evidenceWarning()
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.preferredHeight: 122
                    radius: 4
                    color: window.alpha(Kirigami.Theme.textColor, 0.025)
                    border.width: 1
                    border.color: window.alpha(Kirigami.Theme.textColor, 0.18)

                    Controls.Label {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: 12
                        anchors.topMargin: 9
                        text: qsTr("BOOT PHASES")
                        opacity: 0.82
                        font.family: Kirigami.Theme.smallFont.family
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.weight: Font.DemiBold
                    }

                    Controls.Label {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 12
                        anchors.topMargin: 9
                        text: qsTr("%1 total · select a phase").arg(Story.duration(window.systemBoot.totalMs))
                        color: Kirigami.Theme.textColor
                        opacity: 0.72
                        font: Kirigami.Theme.smallFont
                    }

                    BootTimeline {
                        id: bootTimeline

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 34
                        anchors.bottomMargin: 10
                        stages: window.systemBoot.stages || []
                        stageColors: window.stageColors
                        textColor: Kirigami.Theme.textColor
                    }
                }

                Rectangle {
                    id: phaseDetails

                    readonly property var stage: bootTimeline.selectedIndex >= 0 ? window.systemBoot.stages[bootTimeline.selectedIndex] : ({
                            key: "",
                            label: "",
                            durationMs: 0
                        })
                    readonly property bool services: String(stage.key) === "userspace"
                    readonly property color accent: bootTimeline.selectedIndex >= 0 ? window.stageColors[bootTimeline.selectedIndex % window.stageColors.length] : Kirigami.Theme.highlightColor

                    visible: bootTimeline.selectedIndex >= 0
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.preferredHeight: services && window.criticalPath.length > 0 ? 132 : 92
                    radius: 4
                    color: window.alpha(accent, 0.055)
                    border.width: 1
                    border.color: window.alpha(accent, 0.48)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 7

                            Rectangle {
                                Layout.preferredWidth: 9
                                Layout.preferredHeight: 9
                                radius: 1
                                color: phaseDetails.accent
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                text: qsTr("%1 PHASE").arg(String(phaseDetails.stage.label).toUpperCase())
                                font.family: Kirigami.Theme.smallFont.family
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                font.weight: Font.DemiBold
                            }
                            Controls.Label {
                                text: Story.duration(phaseDetails.stage.durationMs)
                                color: phaseDetails.accent
                                font.weight: Font.DemiBold
                            }
                            Controls.ToolButton {
                                icon.name: "go-up"
                                display: Controls.AbstractButton.IconOnly
                                Accessible.name: qsTr("Collapse phase explanation")
                                onClicked: bootTimeline.selectedIndex = -1
                                Controls.ToolTip.text: qsTr("Collapse")
                                Controls.ToolTip.visible: hovered
                            }
                        }

                        Controls.Label {
                            Layout.fillWidth: true
                            text: window.phaseExplanation(phaseDetails.stage.key)
                            color: Kirigami.Theme.textColor
                            opacity: 0.88
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            visible: phaseDetails.services && window.criticalPath.length > 0
                            Layout.fillWidth: true
                            spacing: 5

                            Controls.Label {
                                text: qsTr("LARGEST CRITICAL-PATH STEPS")
                                opacity: 0.76
                                font.family: Kirigami.Theme.smallFont.family
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: window.criticalPath.slice(0, 3)
                                delegate: Controls.AbstractButton {
                                    id: phaseCriticalUnit

                                    required property var modelData

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    hoverEnabled: true
                                    focusPolicy: Qt.StrongFocus
                                    Accessible.name: qsTr("Inspect %1").arg(phaseCriticalUnit.modelData.name || phaseCriticalUnit.modelData.unit)
                                    onClicked: window.openUnitInspector(phaseCriticalUnit.modelData, "critical")

                                    background: Rectangle {
                                        radius: 2
                                        color: phaseCriticalUnit.down ? window.alpha(phaseDetails.accent, 0.16) : (phaseCriticalUnit.hovered || phaseCriticalUnit.visualFocus ? window.alpha(phaseDetails.accent, 0.09) : window.alpha(Kirigami.Theme.textColor, 0.045))
                                        border.width: 1
                                        border.color: phaseCriticalUnit.visualFocus ? phaseDetails.accent : window.alpha(phaseCriticalUnit.hovered ? phaseDetails.accent : Kirigami.Theme.textColor, phaseCriticalUnit.hovered ? 0.46 : 0.12)
                                    }

                                    contentItem: RowLayout {
                                        spacing: 5
                                        Controls.Label {
                                            Layout.fillWidth: true
                                            text: phaseCriticalUnit.modelData.name
                                            font: Kirigami.Theme.smallFont
                                            elide: Text.ElideRight
                                        }
                                        Controls.Label {
                                            text: Story.duration(phaseCriticalUnit.modelData.durationMs)
                                            color: phaseDetails.accent
                                            font.family: Kirigami.Theme.smallFont.family
                                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Controls.ToolTip.visible: hovered
                                    Controls.ToolTip.text: qsTr("Inspect %1").arg(phaseCriticalUnit.modelData.unit)
                                    HoverHandler {
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    columns: width >= 790 ? 3 : 1
                    columnSpacing: Kirigami.Units.smallSpacing
                    rowSpacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 236
                        Layout.preferredHeight: 270
                        radius: 4
                        color: window.alpha(Kirigami.Theme.textColor, 0.025)
                        border.width: 1
                        border.color: window.alpha(Kirigami.Theme.textColor, 0.18)

                        Controls.Label {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 11
                            text: qsTr("SYSTEM BOOT")
                            opacity: 0.82
                            font.family: Kirigami.Theme.smallFont.family
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            font.weight: Font.DemiBold
                        }

                        StoryDial {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 28
                            width: 150
                            height: 150
                            stages: window.systemBoot.stages || []
                            stageColors: window.stageColors
                            trackColor: Kirigami.Theme.textColor
                        }

                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 88
                            spacing: -2
                            Kirigami.Heading {
                                anchors.horizontalCenter: parent.horizontalCenter
                                level: 2
                                text: Story.duration(window.systemBoot.totalMs)
                            }
                            Controls.Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("TOTAL")
                                opacity: 0.68
                                font.family: Kirigami.Theme.smallFont.family
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                font.weight: Font.DemiBold
                            }
                        }

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 11
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Controls.Label {
                                    Layout.fillWidth: true
                                    text: qsTr("User session target")
                                    opacity: 0.76
                                }
                                Controls.Label {
                                    text: window.userSession.available ? Story.duration(window.userSession.totalMs) : qsTr("Unavailable")
                                    font.weight: Font.DemiBold
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Controls.Label {
                                    Layout.fillWidth: true
                                    text: qsTr("Local baselines")
                                    opacity: 0.76
                                }
                                Controls.Label {
                                    text: String(window.comparison.baselineCount || 0)
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 290
                        Layout.preferredHeight: 270
                        radius: 4
                        color: window.alpha(Kirigami.Theme.textColor, 0.025)
                        border.width: 1
                        border.color: window.alpha(window.criticalPathColor, 0.34)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                Controls.Label {
                                    Layout.fillWidth: true
                                    text: qsTr("CRITICAL PATH")
                                    opacity: 0.86
                                    font.family: Kirigami.Theme.smallFont.family
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    font.weight: Font.DemiBold
                                }
                                Controls.Label {
                                    text: window.coverage.criticalPathAvailable === false
                                        ? qsTr("unavailable")
                                        : (Number(window.snapshot.criticalPathTotal || 0) > window.criticalPath.length
                                            ? qsTr("top %1 of %2").arg(window.criticalPath.length).arg(window.snapshot.criticalPathTotal)
                                            : qsTr("determines ready time"))
                                    color: window.criticalPathColor
                                    font: Kirigami.Theme.smallFont
                                }
                            }
                            Controls.Label {
                                visible: window.coverage.criticalPathAvailable === false
                                Layout.fillWidth: true
                                text: window.coverage.criticalPathError || qsTr("The graphical critical path could not be read.")
                                wrapMode: Text.WordWrap
                                opacity: 0.72
                            }
                            Repeater {
                                model: window.coverage.criticalPathAvailable === false ? [] : window.criticalPath.slice(0, 6)
                                delegate: StoryRow {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    entry: modelData
                                    maximum: window.maximumCritical
                                    accent: window.criticalPathColor
                                    diamond: true
                                    detail: modelData.activatedMs ? qsTr("at %1").arg(Story.duration(modelData.activatedMs)) : ""
                                    onInspectionRequested: function (selectedEntry) {
                                        window.openUnitInspector(selectedEntry, "critical");
                                    }
                                }
                            }
                            Item {
                                Layout.fillHeight: true
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 290
                        Layout.preferredHeight: 270
                        radius: 4
                        color: window.alpha(Kirigami.Theme.textColor, 0.025)
                        border.width: 1
                        border.color: window.alpha(Kirigami.Theme.textColor, 0.18)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                Controls.Label {
                                    Layout.fillWidth: true
                                    text: qsTr("LONG ACTIVATIONS")
                                    opacity: 0.86
                                    font.family: Kirigami.Theme.smallFont.family
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    font.weight: Font.DemiBold
                                }
                                Controls.Label {
                                    text: window.coverage.activationsAvailable === false
                                        ? qsTr("unavailable")
                                        : (Number(window.snapshot.activationTotal || 0) > Math.min(6, window.activations.length)
                                            ? qsTr("top %1 of %2").arg(Math.min(6, window.activations.length)).arg(window.snapshot.activationTotal)
                                            : qsTr("may run in parallel"))
                                    opacity: 0.68
                                    font: Kirigami.Theme.smallFont
                                }
                            }
                            Controls.Label {
                                visible: window.coverage.activationsAvailable === false
                                Layout.fillWidth: true
                                text: window.coverage.activationsError || qsTr("Long activation evidence could not be read.")
                                wrapMode: Text.WordWrap
                                opacity: 0.72
                            }
                            Repeater {
                                model: window.coverage.activationsAvailable === false ? [] : window.activations.slice(0, 6)
                                delegate: StoryRow {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    entry: modelData
                                    maximum: window.maximumActivation
                                    accent: modelData.onCriticalPath ? window.criticalPathColor : Kirigami.Theme.highlightColor
                                    diamond: Boolean(modelData.onCriticalPath)
                                    onInspectionRequested: function (selectedEntry) {
                                        window.openUnitInspector(selectedEntry, selectedEntry.onCriticalPath ? "critical" : "activation");
                                    }
                                }
                            }
                            Item {
                                Layout.fillHeight: true
                            }
                        }
                    }
                }

                Rectangle {
                    visible: Number(window.snapshot.failedUnitCount || 0) > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.preferredHeight: 62
                    radius: 4
                    color: window.alpha(Kirigami.Theme.negativeTextColor, 0.055)
                    border.width: 1
                    border.color: window.alpha(Kirigami.Theme.negativeTextColor, 0.42)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            text: qsTr("FAILED BEFORE DESKTOP")
                            color: Kirigami.Theme.negativeTextColor
                            font.family: Kirigami.Theme.smallFont.family
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            font.weight: Font.DemiBold
                        }

                        Flickable {
                            id: failedUnitsFlickable

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: failedUnitRow.implicitWidth
                            contentHeight: height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            Controls.ScrollBar.horizontal: Controls.ScrollBar {
                                policy: failedUnitRow.implicitWidth > failedUnitsFlickable.width
                                    ? Controls.ScrollBar.AsNeeded
                                    : Controls.ScrollBar.AlwaysOff
                            }

                            Row {
                                id: failedUnitRow
                                height: parent.height
                                spacing: Kirigami.Units.smallSpacing

                                Repeater {
                                    model: window.failedUnits
                                    delegate: Controls.Button {
                                        required property var modelData
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.name || modelData.unit
                                        icon.name: "dialog-warning"
                                        Accessible.name: qsTr("Inspect failed unit %1").arg(text)
                                        onClicked: window.openUnitInspector(modelData, "failure")
                                    }
                                }

                                Controls.Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: Number(window.snapshot.failedUnitCount || 0) > window.failedUnits.length
                                    text: qsTr("+%1 more").arg(Number(window.snapshot.failedUnitCount || 0) - window.failedUnits.length)
                                    opacity: 0.72
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.bottomMargin: Kirigami.Units.largeSpacing
                    Layout.preferredHeight: 86
                    radius: 4
                    color: window.alpha(Kirigami.Theme.textColor, 0.025)
                    border.width: 1
                    border.color: window.alpha(Kirigami.Theme.textColor, 0.18)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: Kirigami.Units.largeSpacing
                        ColumnLayout {
                            Layout.fillWidth: true
                            Controls.Label {
                                text: qsTr("WHAT THIS BOOT SAYS")
                                opacity: 0.82
                                font.family: Kirigami.Theme.smallFont.family
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                font.weight: Font.DemiBold
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                text: window.narrative()
                                wrapMode: Text.WordWrap
                                opacity: 0.94
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                text: bootBackend.snapshotStale
                                    ? qsTr("Long activation is a clue, not proof of delay. This snapshot is stale; booted %1 ago.").arg(Story.age(window.currentBootAgeMs))
                                    : qsTr("Long activation is a clue, not proof of delay. Booted %1 ago.").arg(Story.age(window.currentBootAgeMs))
                                opacity: 0.66
                                font: Kirigami.Theme.smallFont
                            }
                        }

                        ColumnLayout {
                            visible: window.recentBoots.length > 0
                            Layout.preferredWidth: 190
                            Layout.fillHeight: true
                            spacing: 3
                            Controls.Label {
                                Layout.alignment: Qt.AlignRight
                                text: qsTr("BOOT HISTORY")
                                opacity: 0.78
                                font.family: Kirigami.Theme.smallFont.family
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                font.weight: Font.DemiBold
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.alignment: Qt.AlignBottom
                                spacing: 4
                                Item {
                                    Layout.fillWidth: true
                                }
                                Repeater {
                                    model: window.recentBoots
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.minimumWidth: 12
                                        Layout.preferredWidth: 12
                                        Layout.maximumWidth: 12
                                        Layout.alignment: Qt.AlignBottom
                                        Layout.preferredHeight: 10 + 36 * Number(modelData.totalMs || 0) / window.maximumHistory
                                        radius: 1
                                        color: modelData.current ? window.healthColor : window.alpha(Kirigami.Theme.textColor, 0.36)
                                        Controls.ToolTip.visible: historyHover.hovered
                                        Controls.ToolTip.text: Story.duration(modelData.totalMs)
                                        HoverHandler {
                                            id: historyHover
                                        }
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
