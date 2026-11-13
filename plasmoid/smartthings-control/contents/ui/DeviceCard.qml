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
    // Hardware identity. Empty for integrations that don't report it (Zigbee and
    // Z-Wave give a maker at best), so every reader has to skip the gaps.
    required property string manufacturer
    required property string model
    required property string firmware
    required property string integration
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
    // Full TV / speaker state from the daemon, as JSON ("" for anything else).
    required property string media
    // Full appliance state from the daemon, as JSON ("" for anything else).
    required property string appliance
    // Warnings + errors the daemon logged for this device in the last 24 h.
    required property int    issues

    property bool tile: false
    property bool reordering: false
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
    signal machineRequested(string id, string state)   // run | pause
    // mute · input · picture_mode · sound_mode · key · channel_up · channel_down
    signal tvCommand(string id, string action, var value)
    // A wheel turn over a slider scrolls the list instead of moving the slider.
    signal scrollRequested(real delta)
    signal copyRequested(string text)
    signal infoRequested(string title, string body)
    // Open the history tab filtered to this device.
    signal historyRequested(string id)
    // Scene coordinates: the card is being dragged past its own siblings, so the
    // only frame both ends agree on is the window's.
    signal reorderDragged(string key, real sceneX, real sceneY)
    signal reorderDropped()

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

    // ── TV / speaker ──────────────────────────────────────────────────────────
    readonly property var med: {
        if (media === "") return ({})
        try { return JSON.parse(media) } catch (e) { return ({}) }
    }
    readonly property bool muted: med.mute === true
    readonly property var  tvInputs: med.inputs || []
    property bool remoteOpen: false
    readonly property bool tvOnTuner: ["dtv", "digitalTv", "TV", "atv"].indexOf(med.input || "") >= 0

    // What the screen is showing: the foreground app if there is one, else
    // the input under the name the user gave it on the TV.
    readonly property string tvSource: {
        if (med.app) return med.app
        const i = tvInputs.find(x => x.id === med.input)
        return i ? i.name : (med.input || "")
    }

    // ── Appliance ─────────────────────────────────────────────────────────────
    readonly property var appl: {
        if (appliance === "") return ({})
        try { return JSON.parse(appliance) } catch (e) { return ({}) }
    }
    // false only when the machine says so; unknown (null) does not block.
    readonly property bool applRemoteOff: appl.remote === false
    readonly property bool applRunning:   appl.operating === "running" || appl.machine_state === "run"
    readonly property bool applPaused:    appl.operating === "paused"  || appl.machine_state === "pause"
    readonly property bool applActive:    applRunning || applPaused
    readonly property var  applPhases:    appl.phases || []
    readonly property int  applTotalMin:  applPhases.reduce((a, p) => a + (p.min || 0), 0)

    readonly property var jobLabels: ({
        wash: "LAVADO", rinse: "ENJUAGUE", spin: "CENTRIFUGADO", drying: "SECADO",
        weightSensing: "PESANDO", preWash: "PRELAVADO", cooling: "ENFRIANDO",
        wrinklePrevent: "ANTIARRUGAS", finish: "TERMINADO", airWash: "LAVADO AIRE",
        delayWash: "PROGRAMADO",
    })

    readonly property string applStatus: {
        if (!deviceOnline) return "SIN RED"
        if (applRunning) {
            const job = jobLabels[appl.job_state] || ""
            return "EN MARCHA" + (job !== "" ? " · " + job : "")
        }
        if (applPaused) return "EN PAUSA"
        if ((appl.delay_min || 0) > 0) return "PROGRAMADA"
        return isOn ? "LISTA" : "APAGADA"
    }

    // When it ends, as a clock time: "faltan 38 min" is stale a minute later,
    // "termina 17:42" is not.
    readonly property string applEnds: {
        if (!applActive) return ""
        let t = appl.completion || 0
        if (!(t > 0) && appl.remaining_min != null) t = Date.now() / 1000 + appl.remaining_min * 60
        if (!(t > 0)) return ""
        const d = new Date(t * 1000)
        const pad = n => (n < 10 ? "0" : "") + n
        return "TERMINA " + pad(d.getHours()) + ":" + pad(d.getMinutes())
    }

    function fmtMinutes(m) {
        if (m == null) return ""
        return m >= 60 ? Math.floor(m / 60) + " H " + (m % 60 < 10 ? "0" : "") + (m % 60)
                       : m + " MIN"
    }

    // Program settings, in the machine's own terms. The program *name* is not
    // available — the cloud reports an opaque course code with no name table.
    readonly property string applProgram: {
        const out = []
        const t = appl.water_temp || ""
        if (t !== "" && t !== "none") out.push(t === "cold" ? "FRÍA" : t + "°")
        const sp = appl.spin || ""
        if (sp !== "" && sp !== "none")
            out.push(sp === "noSpin" ? "SIN CENTRIF." : sp === "rinseHold" ? "RETENER AGUA"
                                                                         : sp + " RPM")
        const r = appl.rinses || ""
        if (r !== "" && r !== "0") out.push(r + (r === "1" ? " ENJUAGUE" : " ENJUAGUES"))
        const dl = appl.dry_level || ""
        if (dl !== "" && dl !== "none") out.push("SECADO " + (dl === "cupboard" ? "ARMARIO" : dl + " MIN"))
        return out.join(" · ")
    }
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
    readonly property string washerIcon:   Qt.resolvedUrl("../icons/washer.svg")

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
        if (isAppliance) return washerIcon
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

    // ── Identity ──────────────────────────────────────────────────────────────
    // What the device *is*, as opposed to what it is doing: the tooltip answers
    // "which one of these is failing, and what firmware is it on" without a trip
    // to the SmartThings app. Fields an integration doesn't report are dropped
    // rather than shown empty — a column of dashes reads as broken.
    readonly property var infoFields: {
        const rows = []
        if (manufacturer !== "") rows.push(["MARCA",  manufacturer])
        if (model        !== "") rows.push(["MODELO", model])
        if (firmware     !== "") rows.push(["FW",     firmware])
        if (integration  !== "") rows.push(["ENLACE", integration])
        rows.push(["ID", deviceId])
        return rows
    }

    // Aligned on a fixed label column: monospace makes that exact, and the block
    // is the same shape here and in the clipboard.
    readonly property string infoBlock:
        infoFields.map(r => r[0].padEnd(7) + r[1]).join("\n")

    // The panel shows the title and the body separately and the clipboard gets
    // them joined, so what you read is exactly what you paste. The reader is a
    // person looking at a report, hence the room and the plain "no network".
    readonly property string infoTitle:
        deviceName + (roomName !== "" ? "  (" + roomName + ")" : "")
    readonly property string infoBody:
        infoBlock + (deviceOnline ? "" : "\nESTADO SIN RED")
    readonly property string infoClip: infoTitle + "\n" + infoBody

    // A device the history has something to say about. Coral outline rather than
    // a fill: it is a pointer to the history, not a state of the device — a
    // filled coral chip would read as "on".
    component IssueBadge: Rectangle {
        visible: card.issues > 0 && !card.reordering
        implicitWidth:  Math.max(issueLabel.implicitWidth + 6, implicitHeight)
        implicitHeight: Math.round(card.fontXS * 1.7)
        color: card.offlineSurf
        border.color: card.stateColor
        border.width: 1

        Text {
            id: issueLabel
            anchors.centerIn: parent
            text: "!" + card.issues
            font.family: "monospace"
            font.bold: true
            font.pixelSize: card.fontXS
            color: card.stateColor
        }
        MouseArea {
            id: issueArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.historyRequested(card.deviceId)
            QQC2.ToolTip.text: card.issues + (card.issues === 1 ? " incidencia" : " incidencias")
                               + " en 24 h · ver historial"
            QQC2.ToolTip.visible: containsMouse
        }
    }

    // Square-ish outlined button used across the TV controls. `on` fills it
    // coral (a state, e.g. muted); `glyph` is text, `iconName` a theme icon.
    component KeyButton: Rectangle {
        property string glyph: ""
        property string iconName: ""
        property bool on: false
        property string tip: ""
        signal clicked

        implicitWidth:  Math.max(Kirigami.Units.gridUnit * 1.6,
                                 keyText.implicitWidth + Kirigami.Units.gridUnit * 0.7)
        implicitHeight: Kirigami.Units.gridUnit * 1.35
        color: on ? card.stateColor : (keyArea.pressed ? "#33FFFFFF"
                                     : keyArea.containsMouse ? "#1AFFFFFF" : "transparent")
        border.color: on ? card.stateColor : card.structColor
        border.width: 1

        Text {
            id: keyText
            anchors.centerIn: parent
            visible: parent.glyph !== ""
            text: parent.glyph
            font.pixelSize: card.fontXS; font.bold: true; font.family: "monospace"
            color: parent.on ? card.onInk : card.structColor
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            visible: parent.iconName !== ""
            width: Math.round(Kirigami.Units.iconSizes.small * 0.8); height: width
            isMask: true
            source: parent.iconName
            color: parent.on ? card.onInk : card.structColor
        }
        MouseArea {
            id: keyArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: card.deviceOnline
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
            QQC2.ToolTip.text: parent.tip
            QQC2.ToolTip.visible: containsMouse && parent.tip !== ""
            QQC2.ToolTip.delay: 600
        }
    }

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
            // Stays enabled for a tile that can't be controlled: an unreachable
            // device is the one you most want to copy the identity of. What a
            // click does is decided here instead. MouseArea drops clicked() on
            // the second press of a double click, so a tile toggles once and
            // then copies, rather than toggling twice.
            enabled: !card.editingName && !card.confirmingUnlock
            onClicked: {
                if (!card.deviceOnline || !(card.isControllable || card.isLock))
                    return
                card.forceActiveFocus(Qt.MouseFocusReason)
                card.activate()
            }
            onDoubleClicked: card.copyRequested(card.infoClip)
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
                         && (card.subLabel !== "" || card.batteryLow || !card.deviceOnline)
                // A tile has one secondary line, so a battery worth worrying
                // about shares it with the room: as a tile, a button has nowhere
                // else to report it, and silence would read as "fine".
                text: {
                    if (!card.deviceOnline) return "SIN RED"
                    const where = card.subLabel.toUpperCase()
                    if (!card.batteryLow) return where
                    return where !== "" ? where + " · " + card.battery : card.battery
                }
                color: card.batteryLow ? card.stateColor : card.secondColor
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
            // Opposite corner from the rename button rather than beside it: two
            // buttons in the same corner reached into the middle of the tile,
            // where the icon is, and sat on top of it.
            anchors.top:  parent.top
            anchors.left: parent.left
            visible: !card.editingName && !card.confirmingUnlock && !card.reordering
            opacity: tileHover.hovered ? 1 : 0
            enabled: tileHover.hovered
            icon.name: "documentinfo"
            onClicked: card.infoRequested(card.infoTitle, card.infoBody)
            QQC2.ToolTip.text: "Ficha del dispositivo"
            QQC2.ToolTip.visible: hovered

            Behavior on opacity { NumberAnimation { duration: 100 } }
        }

        IssueBadge {
            anchors { top: parent.top; right: parent.right; margins: 3 }
            // The rename button takes this corner on hover.
            opacity: tileHover.hovered ? 0 : 1
            enabled: !tileHover.hovered
        }

        PC3.ToolButton {
            id: renameButton
            anchors.top:   parent.top
            anchors.right: parent.right
            // Present at all times, painted only on hover. Spawning it under the
            // pointer let it take hover from tileHover, which hid it again, which
            // gave hover back — the tile border blinked for as long as you rested
            // in the corner.
            visible: !card.editingName && !card.confirmingUnlock && !card.reordering
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

        // Declared below the controls, so a double click on a slider, a switch or
        // the rename field belongs to that control and never reaches here. It
        // leaves the wheel alone, which keeps the list scrolling over a row.
        MouseArea {
            anchors.fill: parent
            enabled: !card.editingName
            onDoubleClicked: card.copyRequested(card.infoClip)
        }

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

                IssueBadge {
                    visible: card.issues > 0 && !card.reordering && !card.editingName
                }

                Text {
                    text: "SIN RED"
                    visible: !card.deviceOnline && !card.editingName
                    color: card.secondColor
                    font.pixelSize: card.fontXS
                    font.family: "monospace"
                }

                PC3.ToolButton {
                    // Same reveal-by-opacity trick as the rename button below.
                    visible: !card.editingName && !card.reordering
                    opacity: rowHover.hovered ? 1 : 0
                    enabled: rowHover.hovered
                    icon.name: "documentinfo"
                    onClicked: card.infoRequested(card.infoTitle, card.infoBody)
                    QQC2.ToolTip.text: "Ficha del dispositivo"
                    QQC2.ToolTip.visible: hovered

                    Behavior on opacity { NumberAnimation { duration: 100 } }
                }

                PC3.ToolButton {
                    // Holds its slot in the layout whether or not it is showing.
                    // Revealing it with `visible` grew the row's implicit height,
                    // which grew card.height, which reflowed the grid under the
                    // pointer — hover then oscillated and the border blinked.
                    visible: !card.editingName && !card.reordering
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
                    enabled: card.deviceOnline && !card.applRemoteOff
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

                // Speaker: playback + what is playing.
                RowLayout {
                    visible: card.isSpeaker
                    Layout.fillWidth: true
                    spacing: 5

                    KeyButton {
                        iconName: card.playing ? "media-playback-pause" : "media-playback-start"
                        onClicked: card.playbackRequested(card.deviceId, card.playing ? "pause" : "play")
                    }
                    KeyButton {
                        iconName: "media-playback-stop"
                        onClicked: card.playbackRequested(card.deviceId, "stop")
                    }
                    PC3.Label {   // a track title is a name, not a field
                        Layout.fillWidth: true
                        text: card.mediaTitle
                        elide: Text.ElideRight
                        font.pixelSize: card.fontS
                        color: card.secondColor
                    }
                    KeyButton {
                        visible: card.med.mute != null
                        iconName: card.muted ? "audio-volume-muted" : "audio-volume-high"
                        on: card.muted
                        tip: card.muted ? "Quitar silencio" : "Silenciar"
                        onClicked: card.tvCommand(card.deviceId, "mute", !card.muted)
                    }
                }

                // TV: what is on screen, mute, channel.
                RowLayout {
                    visible: card.isTv
                    Layout.fillWidth: true
                    spacing: 5

                    PC3.Label {
                        Layout.fillWidth: true
                        text: card.tvSource
                        elide: Text.ElideRight
                        font.pixelSize: card.fontS
                        font.bold: true
                        color: card.nameColor
                    }
                    // Channels only mean something on the tuner.
                    KeyButton {
                        visible: card.tvOnTuner
                        glyph: "CH−"
                        tip: "Canal anterior"
                        onClicked: card.tvCommand(card.deviceId, "channel_down", undefined)
                    }
                    KeyButton {
                        visible: card.tvOnTuner
                        glyph: "CH+"
                        tip: "Canal siguiente"
                        onClicked: card.tvCommand(card.deviceId, "channel_up", undefined)
                    }
                    KeyButton {
                        visible: card.med.mute != null
                        iconName: card.muted ? "audio-volume-muted" : "audio-volume-high"
                        on: card.muted
                        tip: card.muted ? "Quitar silencio" : "Silenciar"
                        onClicked: card.tvCommand(card.deviceId, "mute", !card.muted)
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

                // Inputs, under the names given on the TV. One input is no choice.
                Flow {
                    visible: card.isTv && card.tvInputs.length > 1
                    Layout.fillWidth: true
                    spacing: 3
                    Repeater {
                        model: card.tvInputs
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool selected: modelData.id === card.med.input
                            width: inTxt.implicitWidth + Kirigami.Units.gridUnit * 0.7
                            height: Kirigami.Units.gridUnit * 1.15
                            color: selected ? card.stateColor : "transparent"
                            border.color: selected ? card.stateColor : card.structColor
                            border.width: 1
                            Text {
                                id: inTxt
                                anchors.centerIn: parent
                                text: parent.modelData.name.toUpperCase()
                                font.pixelSize: card.fontXS; font.bold: true
                                font.family: "monospace"
                                color: parent.selected ? card.onInk : card.structColor
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: card.deviceOnline && !parent.selected
                                cursorShape: Qt.PointingHandCursor
                                onClicked: card.tvCommand(card.deviceId, "input", parent.modelData.id)
                            }
                        }
                    }
                }

                // The remote: folded by default, it is twice the card's height.
                KeyButton {
                    visible: card.isTv && card.med.remote === true
                    glyph: card.remoteOpen ? "CONTROL ▴" : "CONTROL ▾"
                    on: false
                    onClicked: card.remoteOpen = !card.remoteOpen
                }

                RowLayout {
                    visible: card.isTv && card.remoteOpen && card.med.remote === true
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.gridUnit * 0.6

                    // D-pad
                    Grid {
                        columns: 3
                        spacing: 3
                        Layout.alignment: Qt.AlignTop
                        Item { width: 1; height: 1 }
                        KeyButton { glyph: "▲"; onClicked: card.tvCommand(card.deviceId, "key", "UP") }
                        Item { width: 1; height: 1 }
                        KeyButton { glyph: "◀"; onClicked: card.tvCommand(card.deviceId, "key", "LEFT") }
                        KeyButton { glyph: "OK"; onClicked: card.tvCommand(card.deviceId, "key", "OK") }
                        KeyButton { glyph: "▶"; onClicked: card.tvCommand(card.deviceId, "key", "RIGHT") }
                        Item { width: 1; height: 1 }
                        KeyButton { glyph: "▼"; onClicked: card.tvCommand(card.deviceId, "key", "DOWN") }
                        Item { width: 1; height: 1 }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 3

                        Flow {
                            Layout.fillWidth: true
                            spacing: 3
                            KeyButton { glyph: "BACK"; onClicked: card.tvCommand(card.deviceId, "key", "BACK") }
                            KeyButton { glyph: "HOME"; onClicked: card.tvCommand(card.deviceId, "key", "HOME") }
                            KeyButton { glyph: "MENU"; onClicked: card.tvCommand(card.deviceId, "key", "MENU") }
                            KeyButton { glyph: "GUÍA"; onClicked: card.tvCommand(card.deviceId, "key", "GUIDE") }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 3
                            KeyButton { iconName: "media-seek-backward"; tip: "Retroceder"
                                        onClicked: card.tvCommand(card.deviceId, "key", "REWIND") }
                            KeyButton { iconName: "media-playback-start"; tip: "Play"
                                        onClicked: card.tvCommand(card.deviceId, "key", "PLAY") }
                            KeyButton { iconName: "media-playback-pause"; tip: "Pausa"
                                        onClicked: card.tvCommand(card.deviceId, "key", "PAUSE") }
                            KeyButton { iconName: "media-seek-forward"; tip: "Avanzar"
                                        onClicked: card.tvCommand(card.deviceId, "key", "FF") }
                        }
                        // App shortcuts are remote keys, not app ids: the ids
                        // differ by model and region, the keys do not.
                        Flow {
                            Layout.fillWidth: true
                            spacing: 3
                            KeyButton { glyph: "NETFLIX"; onClicked: card.tvCommand(card.deviceId, "key", "FUNCTIONS_NETFLIX") }
                            KeyButton { glyph: "YOUTUBE"; onClicked: card.tvCommand(card.deviceId, "key", "FUNCTIONS_YOUTUBE") }
                            KeyButton { glyph: "PRIME";   onClicked: card.tvCommand(card.deviceId, "key", "FUNCTIONS_AMAZON") }
                            KeyButton { glyph: "DISNEY+"; onClicked: card.tvCommand(card.deviceId, "key", "DISNEY") }
                        }
                    }
                }

                // Picture and sound modes, by the names the TV uses.
                RowLayout {
                    visible: card.isTv && card.remoteOpen
                             && ((card.med.picture_modes || []).length > 0
                                 || (card.med.sound_modes || []).length > 0)
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        visible: (card.med.picture_modes || []).length > 0
                        text: "IMAGEN"
                        font.pixelSize: card.fontXS; font.bold: true; font.family: "monospace"
                        color: card.structColor
                    }
                    QQC2.ComboBox {
                        visible: (card.med.picture_modes || []).length > 0
                        Layout.fillWidth: true
                        font.pixelSize: card.fontXS
                        model: card.med.picture_modes || []
                        currentIndex: (card.med.picture_modes || []).indexOf(card.med.picture_mode)
                        enabled: card.deviceOnline
                        onActivated: card.tvCommand(card.deviceId, "picture_mode", currentText)
                    }
                    Text {
                        visible: (card.med.sound_modes || []).length > 0
                        text: "SONIDO"
                        font.pixelSize: card.fontXS; font.bold: true; font.family: "monospace"
                        color: card.structColor
                    }
                    QQC2.ComboBox {
                        visible: (card.med.sound_modes || []).length > 0
                        Layout.fillWidth: true
                        font.pixelSize: card.fontXS
                        model: card.med.sound_modes || []
                        currentIndex: (card.med.sound_modes || []).indexOf(card.med.sound_mode)
                        enabled: card.deviceOnline
                        onActivated: card.tvCommand(card.deviceId, "sound_mode", currentText)
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

            // ── Appliance ─────────────────────────────────────────────────────
            ColumnLayout {
                visible: card.isAppliance
                Layout.fillWidth: true
                spacing: 4

                // Status + when it ends.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: card.applStatus
                        color: card.applRunning ? card.stateColor : card.nameColor
                        font.pixelSize: card.fontS; font.bold: true; font.family: "monospace"
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: card.applEnds !== ""
                        text: card.applEnds
                        color: card.nameColor
                        font.pixelSize: card.fontXS; font.bold: true; font.family: "monospace"
                    }
                }

                // Progress across the cycle's phases, each as wide as its share
                // of the time — so "enjuague" visibly comes after a long wash.
                Item {
                    visible: card.applActive && card.applPhases.length > 0 && card.applTotalMin > 0
                    Layout.fillWidth: true
                    implicitHeight: phaseLabels.implicitHeight + 8

                    Row {
                        id: phaseBar
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: 5
                        spacing: 2
                        Repeater {
                            model: card.applPhases
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: Math.max(4, (phaseBar.width - phaseBar.spacing
                                                    * (card.applPhases.length - 1))
                                                   * modelData.min / card.applTotalMin)
                                height: phaseBar.height
                                color: "#3C3C3C"
                            }
                        }
                    }
                    // Fill on top of the track, by overall progress.
                    Rectangle {
                        anchors { left: parent.left; top: parent.top }
                        height: 5
                        width: parent.width * Math.max(0, Math.min(100, card.appl.progress || 0)) / 100
                        color: card.applRunning ? card.stateColor : card.secondColor
                    }
                    Row {
                        id: phaseLabels
                        anchors { left: parent.left; right: parent.right; top: phaseBar.bottom; topMargin: 3 }
                        spacing: 2
                        Repeater {
                            model: card.applPhases
                            Text {
                                required property var modelData
                                width: Math.max(4, (phaseLabels.width - phaseLabels.spacing
                                                    * (card.applPhases.length - 1))
                                                   * modelData.min / card.applTotalMin)
                                text: (card.jobLabels[modelData.name] || modelData.name.toUpperCase())
                                elide: Text.ElideRight
                                font.pixelSize: card.fontXS; font.family: "monospace"
                                font.bold: modelData.name === card.appl.job_state
                                color: modelData.name === card.appl.job_state ? card.nameColor
                                                                               : card.secondColor
                            }
                        }
                    }
                }

                // Program settings + child lock.
                RowLayout {
                    visible: card.applProgram !== "" || card.appl.kids_lock === true
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        visible: card.applProgram !== ""
                        text: card.applProgram
                        elide: Text.ElideRight
                        color: card.secondColor
                        font.pixelSize: card.fontXS; font.family: "monospace"
                    }
                    Text {
                        visible: card.appl.kids_lock === true
                        text: "BLOQ. INFANTIL"
                        color: card.secondColor
                        font.pixelSize: card.fontXS; font.bold: true; font.family: "monospace"
                    }
                    Text {
                        visible: !card.applActive && card.applTotalMin > 0 && card.isOn
                        text: card.fmtMinutes(card.applTotalMin)
                        color: card.secondColor
                        font.pixelSize: card.fontXS; font.family: "monospace"
                    }
                }

                // Controls — or why there are none. Smart Control is a button
                // on the machine; nothing the widget sends can turn it on.
                RowLayout {
                    Layout.fillWidth: true
                    visible: card.deviceOnline
                    spacing: 5

                    Rectangle {
                        visible: !card.applRemoteOff && card.isOn
                        implicitWidth:  runRow.implicitWidth + Kirigami.Units.gridUnit * 0.8
                        implicitHeight: Kirigami.Units.gridUnit * 1.25
                        color: "transparent"
                        border.color: card.structColor
                        border.width: 1
                        Row {
                            id: runRow
                            anchors.centerIn: parent
                            spacing: 4
                            Kirigami.Icon {
                                width: Math.round(Kirigami.Units.iconSizes.small * 0.8); height: width
                                isMask: true
                                source: card.applRunning ? "media-playback-pause" : "media-playback-start"
                                color: card.structColor
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.applRunning ? "PAUSAR" : (card.applPaused ? "REANUDAR" : "INICIAR")
                                font.pixelSize: card.fontXS; font.bold: true; font.family: "monospace"
                                color: card.structColor
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.machineRequested(card.deviceId,
                                                             card.applRunning ? "pause" : "run")
                        }
                    }

                    Text {
                        visible: card.applRemoteOff
                        Layout.fillWidth: true
                        text: "SMART CONTROL APAGADO · actívalo en la máquina para controlarla desde aquí"
                        wrapMode: Text.Wrap
                        color: card.secondColor
                        font.pixelSize: card.fontXS; font.family: "monospace"
                    }
                }
            }
        }
    }
    // ── Reorder veil ──────────────────────────────────────────────────────────
    // Last child, so it covers the card whole — sliders, switches and buttons
    // included. A drag that begins on a volume bar has to move the card, not the
    // volume, and that is only true if nothing underneath ever sees the press.
    MouseArea {
        id: reorderVeil
        anchors.fill: parent
        visible: card.reordering
        enabled: card.reordering
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        // The device list is a Flickable: without this it reads a horizontal
        // drag as a scroll and takes the grab away mid-reorder.
        preventStealing: true

        onPositionChanged: (mouse) => {
            if (!pressed) return
            const p = mapToItem(null, mouse.x, mouse.y)
            card.reorderDragged(card.modelKey, p.x, p.y)
        }
        onReleased: card.reorderDropped()

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            // Teal wash while held: the card being carried has to stand out from
            // the ones flowing around it.
            color: reorderVeil.pressed ? "#333DA0AB" : "transparent"
            border.color: card.structColor
            border.width: 1
        }
    }
}
