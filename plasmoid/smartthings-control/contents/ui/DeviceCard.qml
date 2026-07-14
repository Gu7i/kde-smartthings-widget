import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Item {
    id: card

    required property string modelKey
    required property string deviceId
    required property string deviceName
    required property string deviceType
    required property bool   deviceOnline
    required property bool   switchOn
    required property real   brightness
    required property int    outlet
    required property string groupName
    required property string temperature
    required property string humidity
    required property bool   motion
    required property string battery
    required property int    subDevices
    required property string deviceIp
    required property int    buttonKey
    required property int    lockLocked   // -1 unknown, 0 unlocked, 1 locked
    // media (tv / speaker)
    required property int    volume
    required property string playback
    required property string mediaTitle
    required property string tvInput
    // climate (ac)
    required property string acMode
    required property string acModes      // comma-separated
    required property real   setpoint
    required property real   spMin
    required property real   spMax
    required property real   spStep
    required property string acTemp
    required property string acHumidity
    // appliance
    required property string machineState
    required property string jobState

    property bool tile: false
    property bool editingName: false

    signal toggleRequested(string id, var outlet)
    signal brightnessSet(string id, int value)
    signal channelNameSet(string id, int outlet, string name)
    signal lockRequested(string id, bool lock)
    signal volumeSet(string id, int value)
    signal playbackRequested(string id, string command)
    signal acModeSet(string id, string mode)
    signal setpointSet(string id, int value)

    height: tile ? card.width : (listInner.implicitHeight + 20)

    readonly property bool isSwitch:       deviceType === "switch"
    readonly property bool isDimmer:       deviceType === "dimmer"
    readonly property bool isSensor:       deviceType === "sensor"
    readonly property bool isButton:       deviceType === "button"
    readonly property bool isHub:          deviceType === "hub"
    readonly property bool isLock:         deviceType === "lock"
    readonly property bool isTv:           deviceType === "tv"
    readonly property bool isAc:           deviceType === "ac"
    readonly property bool isSpeaker:      deviceType === "speaker"
    readonly property bool isAppliance:    deviceType === "appliance"
    readonly property bool isOn:           switchOn
    readonly property bool isControllable: isSwitch || isDimmer
    readonly property bool hasOnOff:       isSwitch || isDimmer || isTv || isAc || isAppliance
    readonly property bool isMedia:        isTv || isSpeaker
    readonly property bool lockIsLocked:   lockLocked === 1
    readonly property bool lockIsUnlocked: lockLocked === 0

    readonly property var acModeList: acModes.length ? acModes.split(",") : []
    readonly property bool playing:    playback === "playing"

    readonly property bool tileActive: isLock ? lockIsUnlocked : (isOn && hasOnOff)

    readonly property string bulbIcon:     Qt.resolvedUrl("../icons/lightbulb.svg")
    readonly property string lockIcon:     Qt.resolvedUrl("../icons/lock.svg")
    readonly property string lockOpenIcon: Qt.resolvedUrl("../icons/lock-open.svg")

    // Palette: cream surface, teal ink/structure, coral for active/alert states.
    readonly property color creamColor:  "#F2E8D1"
    readonly property color tealColor:   "#3DA0AB"
    readonly property color coralColor:  "#DD664E"
    // Role aliases used across the card:
    readonly property color accentColor: creamColor          // base surface / on-active ink
    readonly property color darkColor:   tealColor           // ink, borders, headers
    readonly property color mutedColor:  Qt.darker(tealColor, 1.3)  // dim teal, secondary text

    // ── Tile (square) ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 0
        color:        tileActive ? coralColor  : accentColor
        border.color: tileActive ? accentColor : darkColor
        border.width: 1
        opacity: deviceOnline ? 1 : 0.6
        visible: card.tile

        MouseArea {
            anchors.fill: parent
            enabled: !card.editingName && deviceOnline && (isControllable || isLock)
            onClicked: {
                if (isLock)
                    card.lockRequested(card.deviceId, lockIsUnlocked)
                else
                    card.toggleRequested(card.deviceId,
                        card.outlet >= 0 ? card.outlet : null)
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: 2

            Item { Layout.fillHeight: true }

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                width:  Kirigami.Units.iconSizes.huge
                height: width
                isMask: true
                source: isLock ? (lockIsUnlocked ? lockOpenIcon : lockIcon) : bulbIcon
                color: tileActive ? accentColor : darkColor
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: !card.editingName
                text: deviceName.toUpperCase()
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                font.bold: true
                font.family: "monospace"
                font.pixelSize: 9
                color: tileActive ? accentColor : darkColor
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: isLock && !card.editingName
                text: lockIsLocked ? "BLOQ" : (lockIsUnlocked ? "OPEN" : "---")
                color: lockIsUnlocked ? accentColor
                     : lockIsLocked  ? coralColor
                     :                 mutedColor
                font.pixelSize: 8
                font.bold: true
                font.family: "monospace"
                horizontalAlignment: Text.AlignHCenter
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: isLock && battery !== "" && !card.editingName
                text: battery
                color: tileActive ? accentColor : mutedColor
                font.pixelSize: 8
                font.family: "monospace"
                horizontalAlignment: Text.AlignHCenter
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: !isLock && groupName !== "" && !card.editingName
                text: groupName.toUpperCase()
                color: tileActive ? accentColor : mutedColor
                font.pixelSize: 8
                font.family: "monospace"
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: card.editingName
                spacing: 2

                QQC2.TextField {
                    id: tileNameField
                    Layout.fillWidth: true
                    text: deviceName
                    horizontalAlignment: Text.AlignHCenter
                    Keys.onEscapePressed: card.editingName = false
                    onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
                    onAccepted: {
                        var t = tileNameField.text.trim()
                        if (t) card.channelNameSet(card.deviceId, card.outlet, t)
                        card.editingName = false
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 2
                    PC3.ToolButton {
                        icon.name: "dialog-cancel"
                        onClicked: card.editingName = false
                    }
                    PC3.ToolButton {
                        icon.name: "dialog-ok-apply"
                        onClicked: tileNameField.accepted()
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        PC3.ToolButton {
            anchors.top:   parent.top
            anchors.right: parent.right
            visible: card.outlet >= 0 && !card.editingName
            icon.name: "document-edit"
            onClicked: card.editingName = true
            QQC2.ToolTip.text: "Renombrar"
            QQC2.ToolTip.visible: hovered
        }

        Text {
            anchors.bottom:  parent.bottom
            anchors.right:   parent.right
            anchors.margins: 3
            visible: !deviceOnline
            text: "OFF"
            font.pixelSize: 7
            font.family: "monospace"
            color: mutedColor
        }
    }

    // ── List row ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 0
        color:        tileActive ? coralColor  : accentColor
        border.color: tileActive ? accentColor : darkColor
        border.width: 1
        opacity: deviceOnline ? 1 : 0.8
        visible: !card.tile

        ColumnLayout {
            id: listInner
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 3

            // ── Title row ─────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Kirigami.Icon {
                    width:  16; height: 16
                    isMask: true
                    source: {
                        if (isHub)       return "network-wired"
                        if (isButton)    return "input-touchpad"
                        if (isSensor)    return "view-statistics"
                        if (isDimmer)    return "brightness-high"
                        if (isTv)        return "video-television"
                        if (isAc)        return "temperature-cold"
                        if (isSpeaker)   return "audio-speakers-symbolic"
                        if (isAppliance) return "washing-machine-symbolic"
                        return bulbIcon
                    }
                    color: tileActive ? accentColor : darkColor
                }

                PC3.Label {
                    Layout.fillWidth: true
                    visible: !card.editingName
                    text: deviceName.toUpperCase()
                    elide: Text.ElideRight
                    font.bold: true
                    font.family: "monospace"
                    font.pixelSize: 11
                    color: tileActive ? accentColor : darkColor
                }

                QQC2.TextField {
                    id: nameField
                    Layout.fillWidth: true
                    visible: card.editingName
                    text: deviceName
                    Keys.onEscapePressed: card.editingName = false
                    onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
                    onAccepted: {
                        var t = nameField.text.trim()
                        if (t) card.channelNameSet(card.deviceId, card.outlet, t)
                        card.editingName = false
                    }
                }

                Text {
                    text: "OFFLINE"
                    visible: !deviceOnline && !card.editingName
                    color: mutedColor
                    font.pixelSize: 8
                    font.family: "monospace"
                }

                PC3.ToolButton {
                    visible: groupName !== "" && !card.editingName
                    icon.name: "document-edit"
                    onClicked: card.editingName = true
                    QQC2.ToolTip.text: "Renombrar"
                    QQC2.ToolTip.visible: hovered
                }

                PC3.ToolButton {
                    visible: card.editingName
                    icon.name: "dialog-ok-apply"
                    onClicked: nameField.accepted()
                }

                QQC2.Switch {
                    visible: hasOnOff && !card.editingName
                    checked: isOn
                    enabled: deviceOnline
                    onToggled: card.toggleRequested(card.deviceId,
                                   card.outlet >= 0 ? card.outlet : null)
                }
            }

            // ── Group label ───────────────────────────────────────────────────
            RowLayout {
                visible: groupName !== "" && !card.editingName
                Layout.fillWidth: true
                spacing: 0
                Item { width: 20 }
                PC3.Label {
                    Layout.fillWidth: true
                    text: groupName.toUpperCase()
                    color: mutedColor
                    font.pixelSize: 9
                    font.family: "monospace"
                    elide: Text.ElideRight
                }
            }

            // ── Sensor: temp / humidity ───────────────────────────────────────
            RowLayout {
                visible: isSensor && (temperature !== "" || humidity !== "")
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    visible: temperature !== ""
                    spacing: 3
                    Kirigami.Icon {
                        width: 14; height: 14
                        isMask: true
                        source: "temperature-normal"
                        color: tileActive ? accentColor : darkColor
                    }
                    PC3.Label {
                        text: temperature
                        font.pixelSize: 10
                        font.family: "monospace"
                        color: tileActive ? accentColor : darkColor
                    }
                }

                RowLayout {
                    visible: humidity !== ""
                    spacing: 3
                    Kirigami.Icon {
                        width: 14; height: 14
                        isMask: true
                        source: "weather-showers-scattered"
                        color: tileActive ? accentColor : darkColor
                    }
                    PC3.Label {
                        text: humidity
                        font.pixelSize: 10
                        font.family: "monospace"
                        color: tileActive ? accentColor : darkColor
                    }
                }

                RowLayout {
                    visible: battery !== ""
                    spacing: 3
                    Kirigami.Icon {
                        width: 14; height: 14
                        isMask: true
                        source: "battery-full"
                        color: mutedColor
                    }
                    PC3.Label {
                        text: battery
                        font.pixelSize: 10
                        font.family: "monospace"
                        color: mutedColor
                    }
                }
            }

            // ── Sensor: motion / contact ──────────────────────────────────────
            RowLayout {
                visible: isSensor && temperature === "" && humidity === ""
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: motion ? "ACTIVE" : "IDLE"
                    color: motion ? coralColor : mutedColor
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                }
                Text {
                    visible: battery !== ""
                    text: battery
                    color: mutedColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
            }

            // ── Button ────────────────────────────────────────────────────────
            RowLayout {
                visible: isButton
                Layout.fillWidth: true
                Text {
                    text: "BTN"
                    color: mutedColor
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                }
                Text {
                    visible: battery !== ""
                    text: battery
                    font.pixelSize: 10
                    font.family: "monospace"
                    color: mutedColor
                }
            }

            // ── Hub ───────────────────────────────────────────────────────────
            RowLayout {
                visible: isHub
                Layout.fillWidth: true
                Text {
                    text: subDevices + " NODES"
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                    color: tileActive ? accentColor : darkColor
                }
                Text {
                    visible: deviceIp !== ""
                    text: deviceIp
                    color: mutedColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
            }

            // ── Dimmer slider ─────────────────────────────────────────────────
            RowLayout {
                visible: isDimmer && isOn
                Layout.fillWidth: true
                Text {
                    text: "DIM"
                    font.pixelSize: 9
                    font.bold: true
                    font.family: "monospace"
                    color: accentColor
                }
                QQC2.Slider {
                    Layout.fillWidth: true
                    from: 1; to: 100; stepSize: 1
                    value: brightness
                    enabled: deviceOnline && isOn
                    onPressedChanged: {
                        if (!pressed)
                            card.brightnessSet(card.deviceId, Math.round(value))
                    }
                }
                Text {
                    text: Math.round(brightness) + "%"
                    font.pixelSize: 9
                    font.family: "monospace"
                    color: accentColor
                }
            }

            // ── Media controls (TV / speaker) ─────────────────────────────────
            ColumnLayout {
                visible: isSpeaker || (isTv && isOn)
                Layout.fillWidth: true
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Rectangle {   // play / pause
                        width: 30; height: 22
                        color: "transparent"
                        border.color: tileActive ? accentColor : darkColor
                        border.width: 1
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 13; height: 13
                            isMask: true
                            source: playing ? "media-playback-pause" : "media-playback-start"
                            color: tileActive ? accentColor : darkColor
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: deviceOnline
                            onClicked: card.playbackRequested(card.deviceId,
                                           playing ? "pause" : "play")
                        }
                    }

                    Rectangle {   // stop
                        width: 30; height: 22
                        color: "transparent"
                        border.color: tileActive ? accentColor : darkColor
                        border.width: 1
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 13; height: 13
                            isMask: true
                            source: "media-playback-stop"
                            color: tileActive ? accentColor : darkColor
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: deviceOnline
                            onClicked: card.playbackRequested(card.deviceId, "stop")
                        }
                    }

                    PC3.Label {
                        Layout.fillWidth: true
                        text: isSpeaker ? mediaTitle : tvInput
                        visible: (isSpeaker ? mediaTitle : tvInput) !== ""
                        elide: Text.ElideRight
                        font.pixelSize: 9
                        font.family: "monospace"
                        color: tileActive ? accentColor : mutedColor
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "VOL"
                        font.pixelSize: 9; font.bold: true; font.family: "monospace"
                        color: tileActive ? accentColor : darkColor
                    }
                    QQC2.Slider {
                        Layout.fillWidth: true
                        from: 0; to: 100; stepSize: 1
                        value: volume
                        enabled: deviceOnline
                        onPressedChanged: {
                            if (!pressed)
                                card.volumeSet(card.deviceId, Math.round(value))
                        }
                    }
                    Text {
                        text: Math.round(volume) + "%"
                        font.pixelSize: 9; font.family: "monospace"
                        color: tileActive ? accentColor : darkColor
                    }
                }
            }

            // ── AC controls ───────────────────────────────────────────────────
            ColumnLayout {
                visible: isAc && isOn
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "SET"
                        font.pixelSize: 9; font.bold: true; font.family: "monospace"
                        color: accentColor
                    }
                    Rectangle {
                        width: 24; height: 22; color: "transparent"
                        border.color: accentColor; border.width: 1
                        Text { anchors.centerIn: parent; text: "−"
                               font.pixelSize: 14; font.bold: true; color: accentColor }
                        MouseArea {
                            anchors.fill: parent
                            enabled: deviceOnline && setpoint > spMin
                            onClicked: card.setpointSet(card.deviceId,
                                           Math.max(spMin, setpoint - spStep))
                        }
                    }
                    Text {
                        text: Math.round(setpoint) + "°"
                        font.pixelSize: 15; font.bold: true; font.family: "monospace"
                        color: accentColor
                    }
                    Rectangle {
                        width: 24; height: 22; color: "transparent"
                        border.color: accentColor; border.width: 1
                        Text { anchors.centerIn: parent; text: "+"
                               font.pixelSize: 14; font.bold: true; color: accentColor }
                        MouseArea {
                            anchors.fill: parent
                            enabled: deviceOnline && setpoint < spMax
                            onClicked: card.setpointSet(card.deviceId,
                                           Math.min(spMax, setpoint + spStep))
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: acTemp !== ""
                        text: "◉ " + acTemp
                        font.pixelSize: 9; font.family: "monospace"; color: accentColor
                    }
                    Text {
                        visible: acHumidity !== ""
                        text: acHumidity
                        font.pixelSize: 9; font.family: "monospace"; color: accentColor
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 3
                    Repeater {
                        model: card.acModeList
                        delegate: Rectangle {
                            required property string modelData
                            width: modeTxt.implicitWidth + 12; height: 20
                            color: modelData === card.acMode ? accentColor : "transparent"
                            border.color: accentColor; border.width: 1
                            Text {
                                id: modeTxt
                                anchors.centerIn: parent
                                text: parent.modelData.toUpperCase()
                                font.pixelSize: 8; font.bold: true; font.family: "monospace"
                                color: parent.modelData === card.acMode ? darkColor : accentColor
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: deviceOnline
                                onClicked: card.acModeSet(card.deviceId, parent.modelData)
                            }
                        }
                    }
                }
            }

            // ── Appliance state ───────────────────────────────────────────────
            RowLayout {
                visible: isAppliance
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: (machineState !== "" ? machineState : "—").toUpperCase()
                    color: machineState === "run" ? coralColor
                                                   : (tileActive ? accentColor : darkColor)
                    font.pixelSize: 10; font.bold: true; font.family: "monospace"
                }
                Text {
                    visible: jobState !== "" && jobState !== "none"
                    text: jobState.toUpperCase()
                    color: tileActive ? accentColor : mutedColor
                    font.pixelSize: 9; font.family: "monospace"
                }
            }
        }
    }
}
