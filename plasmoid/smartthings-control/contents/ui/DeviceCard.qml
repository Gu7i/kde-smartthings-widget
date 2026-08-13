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
    required property string origName    // cloud name, shown when a local alias is set
    required property bool   hasAlias    // deviceName is a widget-local rename
    required property string deviceType
    required property bool   deviceOnline
    required property string roomName
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
    property bool confirmingUnlock: false   // opening a lock asks first

    signal toggleRequested(string id, var outlet)
    signal brightnessSet(string id, int value)
    // Local-only rename; an empty name restores the original cloud name.
    signal renameRequested(string key, string name)
    signal lockRequested(string id, bool lock)
    signal volumeSet(string id, int value)
    signal playbackRequested(string id, string command)
    signal acModeSet(string id, string mode)
    signal setpointSet(string id, int value)
    // A wheel turn over a slider scrolls the list instead of moving the slider.
    signal scrollRequested(real delta)

    // 4:3 rather than square: an icon, a name and a room fit in three quarters of
    // the height, which buys a whole extra row of devices in the same popup.
    readonly property real tileRatio: 0.75

    height: tile ? Math.round(card.width * tileRatio)
                 : (listInner.implicitHeight + Kirigami.Units.gridUnit)

    // Tiles join the tab chain, so the grid is reachable without a mouse.
    activeFocusOnTab: tile && deviceOnline && (isControllable || isLock)

    // What a click, Space or Enter on a tile does.
    function activate() {
        if (!deviceOnline || editingName || confirmingUnlock) return
        if (isLock) {
            // Closing is harmless; opening a door is not — ask first.
            if (lockIsLocked) {
                confirmingUnlock = true
                confirmTimer.restart()
            } else {
                lockRequested(deviceId, true)
            }
        } else if (isControllable) {
            toggleRequested(deviceId, outlet >= 0 ? outlet : null)
        }
    }

    Keys.onSpacePressed:  activate()
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed:  activate()

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

    // A battery at 100 % is noise; one that is running out is worth a line.
    readonly property int  batteryPct: battery !== "" ? parseInt(battery) : -1
    readonly property bool batteryLow: batteryPct >= 0 && batteryPct <= 30

    readonly property bool tileActive: isLock ? lockIsUnlocked : (isOn && hasOnOff)

    // A room that just repeats the device name adds nothing.
    readonly property string roomLabel:
        roomName.toLowerCase() === deviceName.toLowerCase() ? "" : roomName
    // Secondary line: the strip a channel belongs to, otherwise the room.
    readonly property string subLabel: groupName !== "" ? groupName : roomLabel
    // Full context line for list rows.
    readonly property string contextLabel:
        [roomLabel, groupName].filter(function (s) { return s !== "" }).join(" · ")

    readonly property string bulbIcon:     Qt.resolvedUrl("../icons/lightbulb.svg")
    readonly property string lockIcon:     Qt.resolvedUrl("../icons/lock.svg")
    readonly property string lockOpenIcon: Qt.resolvedUrl("../icons/lock-open.svg")
    readonly property string socketIcon:   Qt.resolvedUrl("../icons/socket.svg")

    // One icon rule for both layouts — the grid used to draw a light bulb for
    // everything, including plugs and strip channels.
    readonly property string typeIcon: {
        if (isLock)      return lockIsUnlocked ? lockOpenIcon : lockIcon
        if (isHub)       return "network-wired"
        if (isButton)    return "input-touchpad"
        if (isSensor)    return "view-statistics"
        if (isDimmer)    return "brightness-high"
        if (isTv)        return "video-television"
        if (isAc)        return "temperature-cold"
        if (isSpeaker)   return "audio-speakers-symbolic"
        if (isAppliance) return "washing-machine-symbolic"
        if (outlet >= 0) return socketIcon      // one channel of a power strip
        return bulbIcon
    }

    // ── Palette ───────────────────────────────────────────────────────────────
    readonly property color creamColor:  "#F2E8D1"
    readonly property color tealColor:   "#3DA0AB"
    readonly property color coralColor:  "#DD664E"

    // One colour per function: teal is structure, cream is what you read, coral
    // is state, warm grey is everything secondary. Contrast ratios against the
    // surface each colour actually sits on are noted — all ≥ 4.5:1.
    readonly property color surfaceColor:  "#2A2A2A"   // card ground
    readonly property color activeSurface: "#2E2320"   // card ground, device on
    readonly property color offlineSurf:   "#242424"   // card ground, unreachable
    readonly property color structColor:   tealColor   // borders, chrome (4.66:1)
    readonly property color nameColor:     creamColor  // device name (11.8:1)
    readonly property color secondColor:   "#9C978B"   // room, battery, units (4.93:1)
    readonly property color stateColor:    coralColor  // on / open / alert
    readonly property color onInk:         "#141414"   // ink on a coral fill (5.34:1)

    readonly property color cardSurface: !deviceOnline ? offlineSurf
                                       : tileActive    ? activeSurface : surfaceColor
    readonly property color glyphColor:  !deviceOnline ? secondColor
                                       : tileActive    ? stateColor : secondColor
    readonly property color titleColor:  deviceOnline ? nameColor : secondColor

    // Type scale — follows the desktop font settings (see main.qml).
    readonly property int fontM:  Kirigami.Theme.defaultFont.pixelSize > 0
                                  ? Kirigami.Theme.defaultFont.pixelSize
                                  : Math.round(Kirigami.Units.gridUnit * 0.62)
    readonly property int fontXS: Math.max(7, Math.round(fontM * 0.72))
    readonly property int fontS:  Math.max(8, Math.round(fontM * 0.85))

    // Diagonal hatch for a device the hub can't reach. A texture reads as a
    // different *kind* of state; a dimmed copy of the card just reads as "off".
    component Hatch: Canvas {
        property color lineColor: "#3C3C3C"
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = lineColor
            ctx.lineWidth = 1
            ctx.beginPath()
            for (let x = -height; x < width; x += 6) {
                ctx.moveTo(x, height)
                ctx.lineTo(x + height, 0)
            }
            ctx.stroke()
        }
        onWidthChanged:     requestPaint()
        onHeightChanged:    requestPaint()
        onLineColorChanged: requestPaint()
    }

    // A slider under the cursor must not eat the wheel: scrolling the list past a
    // volume bar would nudge the volume instead. `wheelEnabled: false` doesn't help
    // — org.kde.desktop's Slider does its own wheel handling in the background item
    // (QTBUG-93081) — so this sits above it, swallows the event and scrolls the list.
    // Worse than the nudge, that handler calls increase(), which breaks the value
    // binding and leaves the bar out of sync with the device.
    component SliderWheelGuard: MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => card.scrollRequested(wheel.angleDelta.y || -wheel.angleDelta.x)
    }

    Timer {
        id: confirmTimer
        interval: 5000
        onTriggered: card.confirmingUnlock = false
    }

    // ── Tile (square) ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 0
        color: card.cardSurface
        // No resting border: a grid of outlined rectangles reads as a grille and
        // the cards stop reading as objects. The line comes back only where it
        // carries meaning — hover, keyboard focus, and the confirm step.
        border.color: card.confirmingUnlock ? card.stateColor : card.structColor
        border.width: card.confirmingUnlock ? 2
                    : card.activeFocus      ? 2
                    : tileHover.hovered     ? 1 : 0
        visible: card.tile

        Hatch {
            anchors.fill: parent
            anchors.margins: 1
            visible: !card.deviceOnline
        }

        // State bar: reads across the grid without flooding the card in coral.
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
            height: 3
            color: card.stateColor
            visible: card.tileActive && !card.confirmingUnlock
        }

        HoverHandler {
            id: tileHover
            cursorShape: (card.deviceOnline && (card.isControllable || card.isLock))
                         ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        MouseArea {
            anchors.fill: parent
            enabled: !card.editingName && !card.confirmingUnlock
                     && card.deviceOnline && (card.isControllable || card.isLock)
            onClicked: {
                card.forceActiveFocus(Qt.MouseFocusReason)
                card.activate()
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: 2
            visible: !card.confirmingUnlock

            Item { Layout.fillHeight: true }

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                // Sized off the height: on a 4:3 tile that is what runs out first.
                Layout.preferredWidth:  Math.min(Kirigami.Units.iconSizes.large,
                                                 Math.round(card.height * 0.42))
                Layout.preferredHeight: Layout.preferredWidth
                isMask: true
                source: card.typeIcon
                color: card.glyphColor
            }

            // The name is the one thing you read: desktop sans, sentence case.
            // Everything around it stays monospaced — that is what makes it read
            // as a name rather than as another field.
            PC3.Label {
                Layout.fillWidth: true
                visible: !card.editingName
                text: card.deviceName
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                font.bold: true
                font.pixelSize: card.fontS
                color: card.titleColor
            }

            // Single secondary line: lock state, or where the device lives.
            PC3.Label {
                Layout.fillWidth: true
                visible: card.isLock && !card.editingName
                text: (card.lockIsLocked ? "BLOQ" : (card.lockIsUnlocked ? "ABIERTA" : "---"))
                      + (card.batteryLow ? " · " + card.battery : "")
                color: (card.lockIsUnlocked || card.batteryLow) ? card.stateColor
                                                                : card.secondColor
                font.pixelSize: card.fontXS
                font.bold: true
                font.family: "monospace"
                horizontalAlignment: Text.AlignHCenter
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: !card.isLock && !card.editingName
                         && (card.subLabel !== "" || !card.deviceOnline)
                text: card.deviceOnline ? card.subLabel.toUpperCase() : "SIN RED"
                color: card.secondColor
                font.pixelSize: card.fontXS
                font.bold: !card.deviceOnline
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
                    text: card.deviceName
                    horizontalAlignment: Text.AlignHCenter
                    placeholderText: card.origName
                    font.pixelSize: card.fontS
                    Keys.onEscapePressed: card.editingName = false
                    onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
                    onAccepted: {
                        card.renameRequested(card.modelKey, tileNameField.text.trim())
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
                        visible: card.hasAlias
                        icon.name: "edit-undo"
                        onClicked: {
                            card.renameRequested(card.modelKey, "")
                            card.editingName = false
                        }
                        QQC2.ToolTip.text: "Restaurar «" + card.origName + "»"
                        QQC2.ToolTip.visible: hovered
                    }
                    PC3.ToolButton {
                        icon.name: "dialog-ok-apply"
                        onClicked: tileNameField.accepted()
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        // ── Unlock confirmation ───────────────────────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            visible: card.confirmingUnlock
            spacing: Kirigami.Units.smallSpacing

            Item { Layout.fillHeight: true }

            PC3.Label {
                Layout.fillWidth: true
                text: "¿ABRIR?"
                horizontalAlignment: Text.AlignHCenter
                font.bold: true
                font.family: "monospace"
                font.pixelSize: card.fontS
                color: card.stateColor
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    implicitWidth:  Kirigami.Units.gridUnit * 1.5
                    implicitHeight: Kirigami.Units.gridUnit * 1.3
                    color: "transparent"
                    border.color: card.secondColor
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: card.fontS
                        color: card.secondColor
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.confirmingUnlock = false
                    }
                }

                Rectangle {
                    implicitWidth:  Kirigami.Units.gridUnit * 1.5
                    implicitHeight: Kirigami.Units.gridUnit * 1.3
                    color: card.stateColor
                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        font.bold: true
                        font.pixelSize: card.fontS
                        color: card.onInk
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            card.confirmingUnlock = false
                            confirmTimer.stop()
                            card.lockRequested(card.deviceId, false)
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        PC3.ToolButton {
            anchors.top:   parent.top
            anchors.right: parent.right
            // Present at all times, painted only on hover. Spawning it under the
            // pointer let it take hover from tileHover, which hid it again, which
            // gave hover back — the tile border blinked for as long as you rested
            // in the corner.
            visible: !card.editingName && !card.confirmingUnlock
            opacity: tileHover.hovered ? 1 : 0
            enabled: tileHover.hovered
            icon.name: "document-edit"
            onClicked: card.editingName = true
            QQC2.ToolTip.text: card.hasAlias ? "Renombrar (original: " + card.origName + ")"
                                             : "Renombrar solo en este widget"
            QQC2.ToolTip.visible: hovered

            Behavior on opacity { NumberAnimation { duration: 100 } }
        }

    }

    // ── List row ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 0
        color: card.cardSurface
        border.color: card.structColor
        border.width: rowHover.hovered ? 1 : 0
        visible: !card.tile

        Hatch {
            anchors.fill: parent
            anchors.margins: 1
            visible: !card.deviceOnline
        }

        Rectangle {   // state bar, along the leading edge of the row
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 1 }
            width: 3
            color: card.stateColor
            visible: card.tileActive
        }

        HoverHandler { id: rowHover }

        ColumnLayout {
            id: listInner
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                margins: Kirigami.Units.smallSpacing * 2
            }
            spacing: 3

            // ── Title row ─────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Kirigami.Icon {
                    Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    isMask: true
                    source: card.typeIcon
                    color: card.glyphColor
                }

                PC3.Label {
                    Layout.fillWidth: true
                    visible: !card.editingName
                    text: card.deviceName
                    elide: Text.ElideRight
                    font.bold: true
                    font.pixelSize: card.fontM
                    color: card.titleColor
                }

                QQC2.TextField {
                    id: nameField
                    Layout.fillWidth: true
                    visible: card.editingName
                    text: card.deviceName
                    placeholderText: card.origName
                    font.pixelSize: card.fontS
                    Keys.onEscapePressed: card.editingName = false
                    onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
                    onAccepted: {
                        card.renameRequested(card.modelKey, nameField.text.trim())
                        card.editingName = false
                    }
                }

                Text {
                    text: "SIN RED"
                    visible: !card.deviceOnline && !card.editingName
                    color: card.secondColor
                    font.pixelSize: card.fontXS
                    font.family: "monospace"
                }

                PC3.ToolButton {
                    // Holds its slot in the layout whether or not it is showing.
                    // Revealing it with `visible` grew the row's implicit height,
                    // which grew card.height, which reflowed the grid under the
                    // pointer — hover then oscillated and the border blinked.
                    visible: !card.editingName
                    opacity: rowHover.hovered ? 1 : 0
                    enabled: rowHover.hovered
                    icon.name: "document-edit"
                    onClicked: card.editingName = true
                    QQC2.ToolTip.text: card.hasAlias ? "Renombrar (original: " + card.origName + ")"
                                                     : "Renombrar solo en este widget"
                    QQC2.ToolTip.visible: hovered

                    Behavior on opacity { NumberAnimation { duration: 100 } }
                }

                PC3.ToolButton {
                    visible: card.editingName && card.hasAlias
                    icon.name: "edit-undo"
                    onClicked: {
                        card.renameRequested(card.modelKey, "")
                        card.editingName = false
                    }
                    QQC2.ToolTip.text: "Restaurar «" + card.origName + "»"
                    QQC2.ToolTip.visible: hovered
                }

                PC3.ToolButton {
                    visible: card.editingName
                    icon.name: "dialog-cancel"
                    onClicked: card.editingName = false
                }

                PC3.ToolButton {
                    visible: card.editingName
                    icon.name: "dialog-ok-apply"
                    onClicked: nameField.accepted()
                }

                QQC2.Switch {
                    visible: card.hasOnOff && !card.editingName
                    checked: card.isOn
                    enabled: card.deviceOnline
                    onToggled: card.toggleRequested(card.deviceId,
                                   card.outlet >= 0 ? card.outlet : null)
                }
            }

            // ── Room / group label ────────────────────────────────────────────
            RowLayout {
                visible: card.contextLabel !== "" && !card.editingName
                Layout.fillWidth: true
                spacing: 0
                Item {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
                }
                PC3.Label {
                    Layout.fillWidth: true
                    text: card.contextLabel.toUpperCase()
                    color: card.secondColor
                    font.pixelSize: card.fontXS
                    font.family: "monospace"
                    elide: Text.ElideRight
                }
            }

            // ── Sensor: temp / humidity ───────────────────────────────────────
            RowLayout {
                visible: card.isSensor && (card.temperature !== "" || card.humidity !== "")
                Layout.fillWidth: true
                spacing: Kirigami.Units.gridUnit * 0.7

                RowLayout {
                    visible: card.temperature !== ""
                    spacing: 3
                    Kirigami.Icon {
                        Layout.preferredWidth:  Math.round(Kirigami.Units.iconSizes.small * 0.85)
                        Layout.preferredHeight: Math.round(Kirigami.Units.iconSizes.small * 0.85)
                        isMask: true
                        source: "temperature-normal"
                        color: card.structColor
                    }
                    PC3.Label {
                        text: card.temperature
                        font.pixelSize: card.fontS
                        font.family: "monospace"
                        color: card.nameColor
                    }
                }

                RowLayout {
                    visible: card.humidity !== ""
                    spacing: 3
                    Kirigami.Icon {
                        Layout.preferredWidth:  Math.round(Kirigami.Units.iconSizes.small * 0.85)
                        Layout.preferredHeight: Math.round(Kirigami.Units.iconSizes.small * 0.85)
                        isMask: true
                        source: "weather-showers-scattered"
                        color: card.structColor
                    }
                    PC3.Label {
                        text: card.humidity
                        font.pixelSize: card.fontS
                        font.family: "monospace"
                        color: card.nameColor
                    }
                }

                RowLayout {
                    visible: card.battery !== ""
                    spacing: 3
                    Kirigami.Icon {
                        Layout.preferredWidth:  Math.round(Kirigami.Units.iconSizes.small * 0.85)
                        Layout.preferredHeight: Math.round(Kirigami.Units.iconSizes.small * 0.85)
                        isMask: true
                        source: "battery-full"
                        color: card.secondColor
                    }
                    PC3.Label {
                        text: card.battery
                        font.pixelSize: card.fontS
                        font.family: "monospace"
                        color: card.secondColor
                    }
                }
            }

            // ── Sensor: motion / contact ──────────────────────────────────────
            RowLayout {
                visible: card.isSensor && card.temperature === "" && card.humidity === ""
                Layout.fillWidth: true
                spacing: Kirigami.Units.gridUnit * 0.7
                Text {
                    text: card.motion ? "ACTIVO" : "EN REPOSO"
                    color: card.motion ? card.stateColor : card.secondColor
                    font.pixelSize: card.fontS
                    font.bold: true
                    font.family: "monospace"
                }
                Text {
                    visible: card.battery !== ""
                    text: card.battery
                    color: card.secondColor
                    font.pixelSize: card.fontS
                    font.family: "monospace"
                }
            }

            // ── Button ────────────────────────────────────────────────────────
            RowLayout {
                visible: card.isButton
                Layout.fillWidth: true
                Text {
                    text: "BTN"
                    color: card.structColor
                    font.pixelSize: card.fontS
                    font.bold: true
                    font.family: "monospace"
                }
                Text {
                    visible: card.battery !== ""
                    text: card.battery
                    font.pixelSize: card.fontS
                    font.family: "monospace"
                    color: card.secondColor
                }
            }

            // ── Hub ───────────────────────────────────────────────────────────
            RowLayout {
                visible: card.isHub
                Layout.fillWidth: true
                Text {
                    text: card.subDevices + " NODOS"
                    font.pixelSize: card.fontS
                    font.bold: true
                    font.family: "monospace"
                    color: card.nameColor
                }
                Text {
                    visible: card.deviceIp !== ""
                    text: card.deviceIp
                    color: card.secondColor
                    font.pixelSize: card.fontS
                    font.family: "monospace"
                }
            }

            // ── Dimmer slider ─────────────────────────────────────────────────
            RowLayout {
                visible: card.isDimmer && card.isOn
                Layout.fillWidth: true
                Text {
                    text: "DIM"
                    font.pixelSize: card.fontXS
                    font.bold: true
                    font.family: "monospace"
                    color: card.structColor
                }
                QQC2.Slider {
                    Layout.fillWidth: true
                    from: 1; to: 100; stepSize: 1
                    value: card.brightness
                    enabled: card.deviceOnline && card.isOn
                    onPressedChanged: {
                        if (!pressed)
                            card.brightnessSet(card.deviceId, Math.round(value))
                    }
                    SliderWheelGuard {}
                }
                Text {
                    text: Math.round(card.brightness) + "%"
                    font.pixelSize: card.fontXS
                    font.family: "monospace"
                    color: card.nameColor
                }
            }

            // ── Media controls (TV / speaker) ─────────────────────────────────
            ColumnLayout {
                visible: card.isSpeaker || (card.isTv && card.isOn)
                Layout.fillWidth: true
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Rectangle {   // play / pause
                        implicitWidth:  Kirigami.Units.gridUnit * 1.7
                        implicitHeight: Kirigami.Units.gridUnit * 1.25
                        color: "transparent"
                        border.color: card.structColor
                        border.width: 1
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: Math.round(Kirigami.Units.iconSizes.small * 0.8); height: width
                            isMask: true
                            source: card.playing ? "media-playback-pause" : "media-playback-start"
                            color: card.structColor
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: card.deviceOnline
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.playbackRequested(card.deviceId,
                                           card.playing ? "pause" : "play")
                        }
                    }

                    Rectangle {   // stop
                        implicitWidth:  Kirigami.Units.gridUnit * 1.7
                        implicitHeight: Kirigami.Units.gridUnit * 1.25
                        color: "transparent"
                        border.color: card.structColor
                        border.width: 1
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: Math.round(Kirigami.Units.iconSizes.small * 0.8); height: width
                            isMask: true
                            source: "media-playback-stop"
                            color: card.structColor
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: card.deviceOnline
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.playbackRequested(card.deviceId, "stop")
                        }
                    }

                    PC3.Label {   // a track title is a name, not a field
                        Layout.fillWidth: true
                        text: card.isSpeaker ? card.mediaTitle : card.tvInput
                        visible: (card.isSpeaker ? card.mediaTitle : card.tvInput) !== ""
                        elide: Text.ElideRight
                        font.pixelSize: card.fontS
                        color: card.secondColor
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "VOL"
                        font.pixelSize: card.fontXS; font.bold: true; font.family: "monospace"
                        color: card.structColor
                    }
                    QQC2.Slider {
                        Layout.fillWidth: true
                        from: 0; to: 100; stepSize: 1
                        value: card.volume
                        enabled: card.deviceOnline
                        onPressedChanged: {
                            if (!pressed)
                                card.volumeSet(card.deviceId, Math.round(value))
                        }
                        SliderWheelGuard {}
                    }
                    Text {
                        text: Math.round(card.volume) + "%"
                        font.pixelSize: card.fontXS; font.family: "monospace"
                        color: card.nameColor
                    }
                }
            }

            // ── AC controls ───────────────────────────────────────────────────
            ColumnLayout {
                visible: card.isAc && card.isOn
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "SET"
                        font.pixelSize: card.fontXS; font.bold: true; font.family: "monospace"
                        color: card.structColor
                    }
                    Rectangle {
                        implicitWidth:  Kirigami.Units.gridUnit * 1.35
                        implicitHeight: Kirigami.Units.gridUnit * 1.25
                        color: "transparent"
                        border.color: card.structColor; border.width: 1
                        Text { anchors.centerIn: parent; text: "−"
                               font.pixelSize: card.fontM + 3; font.bold: true
                               color: card.structColor }
                        MouseArea {
                            anchors.fill: parent
                            enabled: card.deviceOnline && card.setpoint > card.spMin
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.setpointSet(card.deviceId,
                                           Math.max(card.spMin, card.setpoint - card.spStep))
                        }
                    }
                    Text {
                        text: Math.round(card.setpoint) + "°"
                        font.pixelSize: card.fontM + 4; font.bold: true; font.family: "monospace"
                        color: card.nameColor
                    }
                    Rectangle {
                        implicitWidth:  Kirigami.Units.gridUnit * 1.35
                        implicitHeight: Kirigami.Units.gridUnit * 1.25
                        color: "transparent"
                        border.color: card.structColor; border.width: 1
                        Text { anchors.centerIn: parent; text: "+"
                               font.pixelSize: card.fontM + 3; font.bold: true
                               color: card.structColor }
                        MouseArea {
                            anchors.fill: parent
                            enabled: card.deviceOnline && card.setpoint < card.spMax
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.setpointSet(card.deviceId,
                                           Math.min(card.spMax, card.setpoint + card.spStep))
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: card.acTemp !== ""
                        text: "◉ " + card.acTemp
                        font.pixelSize: card.fontXS; font.family: "monospace"
                        color: card.secondColor
                    }
                    Text {
                        visible: card.acHumidity !== ""
                        text: card.acHumidity
                        font.pixelSize: card.fontXS; font.family: "monospace"
                        color: card.secondColor
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 3
                    Repeater {
                        model: card.acModeList
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool selected: modelData === card.acMode
                            width: modeTxt.implicitWidth + Kirigami.Units.gridUnit * 0.7
                            height: Kirigami.Units.gridUnit * 1.15
                            color: selected ? card.stateColor : "transparent"
                            border.color: selected ? card.stateColor : card.structColor
                            border.width: 1
                            Text {
                                id: modeTxt
                                anchors.centerIn: parent
                                text: parent.modelData.toUpperCase()
                                font.pixelSize: card.fontXS; font.bold: true
                                font.family: "monospace"
                                color: parent.selected ? card.onInk : card.structColor
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: card.deviceOnline
                                cursorShape: Qt.PointingHandCursor
                                onClicked: card.acModeSet(card.deviceId, parent.modelData)
                            }
                        }
                    }
                }
            }

            // ── Appliance state ───────────────────────────────────────────────
            RowLayout {
                visible: card.isAppliance
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: (card.machineState !== "" ? card.machineState : "—").toUpperCase()
                    color: card.machineState === "run" ? card.stateColor : card.nameColor
                    font.pixelSize: card.fontS; font.bold: true; font.family: "monospace"
                }
                Text {
                    visible: card.jobState !== "" && card.jobState !== "none"
                    text: card.jobState.toUpperCase()
                    color: card.secondColor
                    font.pixelSize: card.fontXS; font.family: "monospace"
                }
            }
        }
    }
}
