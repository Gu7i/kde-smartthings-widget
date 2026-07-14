import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string daemonUrl: "http://127.0.0.1:7182"
    readonly property int pollMs: 8000

    // Palette: dark surface, teal ink/structure, coral for active/alert states,
    // cream for secondary text.
    readonly property color darkBg:      "#1C1C1C"
    readonly property color creamColor:  "#F2E8D1"
    readonly property color tealColor:   "#3DA0AB"
    readonly property color coralColor:  "#DD664E"
    // Role aliases used across the UI:
    readonly property color accentColor: darkBg      // base surface / background
    readonly property color darkColor:   tealColor   // ink, borders, headers

    property int activeTab: 0
    readonly property var tabDefs: [
        { label: "Luces",      types: ["switch", "dimmer"] },
        { label: "Clima",      types: ["ac"] },
        { label: "Multimedia", types: ["tv", "speaker"] },
        { label: "Aparatos",   types: ["appliance"] },
        { label: "Sensores",   types: ["sensor"] },
        { label: "Botones",    types: ["button"] },
        { label: "Hubs",       types: ["hub"] },
    ]

    preferredRepresentation: compactRepresentation
    toolTipMainText: "SmartThings Control"
    toolTipSubText: daemonOk ? `${deviceModel.count} dispositivos` : "Daemon offline"

    // ── Compact (panel icon) ──────────────────────────────────────────────────
    compactRepresentation: Item {
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            source: daemonOk ? "smartphone" : "network-offline"
            opacity: daemonOk ? 1 : 0.5
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    // ── Full (popup) ──────────────────────────────────────────────────────────
    fullRepresentation: Item {
        implicitWidth:  Kirigami.Units.gridUnit * 30
        implicitHeight: Kirigami.Units.gridUnit * 24
        Layout.preferredWidth:  Kirigami.Units.gridUnit * 30
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24
        Layout.minimumWidth:    Kirigami.Units.gridUnit * 30

        Rectangle {
            anchors.fill: parent
            color: root.accentColor

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                // ── Header ────────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Column {
                        spacing: 1
                        RowLayout {
                            spacing: 5
                            Text {
                                text: "SMARTTHINGS"
                                font.bold: true
                                font.pixelSize: 20
                                font.family: "monospace"
                                font.letterSpacing: 2
                                color: root.darkColor
                            }
                            Rectangle {
                                width: 5; height: 5; radius: 3
                                color: daemonOk ? root.darkColor : root.coralColor
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                        Text {
                            text: "ST " + ("000" + deviceModel.count).slice(-3) + "-B"
                            font.pixelSize: 9
                            font.family: "monospace"
                            color: root.darkColor
                            opacity: 0.5
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: !daemonOk
                        text: "DAEMON OFFLINE"
                        font.pixelSize: 9
                        font.bold: true
                        font.family: "monospace"
                        color: root.coralColor
                    }

                    Rectangle {
                        width: 28; height: 28
                        color: "transparent"
                        border.color: root.darkColor
                        border.width: 1

                        MouseArea {
                            anchors.fill: parent
                            onClicked: fetchDevices()
                            QQC2.ToolTip.text: "Actualizar"
                            QQC2.ToolTip.visible: containsMouse
                            hoverEnabled: true

                            Text {
                                anchors.centerIn: parent
                                text: "↺"
                                font.pixelSize: 16
                                font.bold: true
                                color: root.darkColor
                            }
                        }
                    }
                }

                // ── Divider ───────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: root.darkColor
                    opacity: 0.3
                }

                // ── Tab bar (wraps to a second row when needed) ───────────────
                Flow {
                    Layout.fillWidth: true
                    spacing: 3

                    Repeater {
                        model: root.tabDefs
                        delegate: Rectangle {
                            property bool active: root.activeTab === index
                            width: tabLabel.implicitWidth + 16
                            height: 22
                            color: active ? root.darkColor : "transparent"
                            border.color: root.darkColor
                            border.width: 1

                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: modelData.label.toUpperCase()
                                font.bold: true
                                font.pixelSize: 9
                                font.family: "monospace"
                                font.letterSpacing: 1
                                color: active ? root.accentColor : root.darkColor
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.activeTab = index
                            }
                        }
                    }
                }

                // ── Device list ───────────────────────────────────────────────
                QQC2.ScrollView {
                    id: scrollView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ColumnLayout {
                        width: scrollView.availableWidth
                        spacing: 4

                        Flow {
                            id: deviceFlow
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: deviceModel

                                DeviceCard {
                                    tile: deviceType === "switch" || deviceType === "lock"
                                    visible: root.tabDefs[root.activeTab].types.indexOf(deviceType) >= 0
                                    width: {
                                        if (!tile) return deviceFlow.width
                                        return Math.floor((deviceFlow.width - 4 * 5) / 6)
                                    }
                                    onToggleRequested:    (id, out) => toggleDevice(id, out)
                                    onBrightnessSet:      (id, val) => setBrightness(id, val)
                                    onChannelNameSet:     (id, out, name) => renameChannel(id, out, name)
                                    onLockRequested:      (id, lock) => lockDevice(id, lock)
                                    onVolumeSet:          (id, val) => setVolume(id, val)
                                    onPlaybackRequested:  (id, cmd) => mediaCmd(id, cmd)
                                    onAcModeSet:          (id, mode) => setAcMode(id, mode)
                                    onSetpointSet:        (id, val) => setSetpoint(id, val)
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            topPadding: Kirigami.Units.gridUnit
                            opacity: 0.45
                            text: "// SIN DISPOSITIVOS //"
                            font.family: "monospace"
                            font.pixelSize: 10
                            color: root.darkColor
                            visible: {
                                if (deviceModel.count === 0) return false
                                var types = root.tabDefs[root.activeTab].types
                                for (var i = 0; i < deviceModel.count; i++) {
                                    if (types.indexOf(deviceModel.get(i).deviceType) >= 0) return false
                                }
                                return true
                            }
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            topPadding: Kirigami.Units.gridUnit
                            opacity: 0.45
                            text: "// CARGANDO... //"
                            font.family: "monospace"
                            font.pixelSize: 10
                            color: root.darkColor
                            visible: deviceModel.count === 0 && daemonOk
                        }
                    }
                }

                // ── Footer ────────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: root.darkColor
                    opacity: 0.3
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "#3DA0AB"
                        font.pixelSize: 8
                        font.family: "monospace"
                        color: root.darkColor
                        opacity: 0.4
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "SAMSUNG™"
                        font.pixelSize: 8
                        font.bold: true
                        font.family: "monospace"
                        color: root.darkColor
                        opacity: 0.4
                    }
                }
            }
        }
    }

    // ── Data model ────────────────────────────────────────────────────────────
    ListModel { id: deviceModel }

    property bool daemonOk: false

    // ── Polling timer ─────────────────────────────────────────────────────────
    Timer {
        id: pollTimer
        interval: root.pollMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchDevices()
    }

    // ── API helpers ───────────────────────────────────────────────────────────
    function fetchDevices() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", daemonUrl + "/devices")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                daemonOk = true
                applyDevices(JSON.parse(xhr.responseText))
            } else {
                daemonOk = false
            }
        }
        xhr.ontimeout = () => { daemonOk = false }
        xhr.onerror   = () => { daemonOk = false }
        xhr.send()
    }

    function applyDevices(list) {
        const validKeys = new Set()
        list.forEach(d => {
            if (d.type === "multi_switch") {
                const ch = (d.state || {}).channels || []
                ch.forEach((_, i) => validKeys.add(d.id + "_" + i))
            } else {
                validKeys.add(d.id)
            }
        })

        for (let i = deviceModel.count - 1; i >= 0; i--) {
            if (!validKeys.has(deviceModel.get(i).modelKey))
                deviceModel.remove(i)
        }

        list.forEach(d => {
            if (d.type === "multi_switch") {
                const s = d.state || {}
                const channels  = s.channels      || []
                const chNames   = s.channel_names || []
                channels.forEach((on, i) => {
                    const key  = d.id + "_" + i
                    const idx  = findIndex(key)
                    const flat = {
                        modelKey:     key,
                        deviceId:     d.id,
                        deviceName:   chNames[i] || ("Canal " + (i + 1)),
                        deviceType:   "switch",
                        deviceOnline: d.online,
                        switchOn:     on,
                        outlet:       i,
                        groupName:    d.name,
                        brightness:   100,
                        temperature:  "",
                        humidity:     "",
                        motion:       false,
                        battery:      "",
                        subDevices:   0,
                        deviceIp:     "",
                        buttonKey:    0,
                        lockLocked:   -1,
                        volume:       0,
                        playback:     "",
                        mediaTitle:   "",
                        tvInput:      "",
                        acMode:       "",
                        acModes:      "",
                        setpoint:     0,
                        spMin:        16,
                        spMax:        30,
                        spStep:       1,
                        acTemp:       "",
                        acHumidity:   "",
                        machineState: "",
                        jobState:     "",
                    }
                    if (idx >= 0) deviceModel.set(idx, flat)
                    else          deviceModel.append(flat)
                })
            } else {
                const key = d.id
                const idx = findIndex(key)
                const flat = flatDevice(d)
                if (idx >= 0) deviceModel.set(idx, flat)
                else          deviceModel.append(flat)
            }
        })
    }

    function flatDevice(d) {
        const s = d.state || {}
        return {
            modelKey:     d.id,
            deviceId:     d.id,
            deviceName:   d.name,
            deviceType:   d.type,
            deviceOnline: d.online,
            switchOn:     s.on ?? false,
            outlet:       -1,
            groupName:    "",
            brightness:   s.brightness ?? 100,
            temperature:  s.temperature != null ? s.temperature + "°C" : "",
            humidity:     s.humidity    != null ? s.humidity    + "%" : "",
            motion:       s.motion      ?? false,
            battery:      s.battery     != null ? Math.round(s.battery) + "%" : "",
            subDevices:   s.sub_devices ?? 0,
            deviceIp:     s.ip          ?? "",
            buttonKey:    s.key         ?? 0,
            lockLocked:   s.locked === true ? 1 : (s.locked === false ? 0 : -1),
            // media (tv / speaker)
            volume:       s.volume      ?? 0,
            playback:     s.playback    ?? "",
            mediaTitle:   s.title       ?? "",
            tvInput:      s.input       ?? "",
            // climate (ac)
            acMode:       s.mode        ?? "",
            acModes:      (s.modes || []).join(","),
            setpoint:     s.setpoint    ?? 0,
            spMin:        s.sp_min      ?? 16,
            spMax:        s.sp_max      ?? 30,
            spStep:       s.sp_step     ?? 1,
            acTemp:       s.temperature != null ? s.temperature + "°C" : "",
            acHumidity:   s.humidity    != null ? s.humidity    + "%" : "",
            // appliance
            machineState: s.machine_state ?? "",
            jobState:     s.job_state     ?? "",
        }
    }

    function findIndex(key) {
        for (let i = 0; i < deviceModel.count; i++)
            if (deviceModel.get(i).modelKey === key) return i
        return -1
    }

    function toggleDevice(id, outlet) {
        const key = (outlet != null && outlet >= 0) ? id + "_" + outlet : id
        for (let i = 0; i < deviceModel.count; i++) {
            if (deviceModel.get(i).modelKey === key) {
                deviceModel.setProperty(i, "switchOn", !deviceModel.get(i).switchOn)
                break
            }
        }
        const body = (outlet != null && outlet >= 0) ? JSON.stringify({outlet}) : ""
        postAction(id, "toggle", body)
    }

    function setBrightness(id, val) {
        postAction(id, "brightness", JSON.stringify({value: val}))
    }

    function lockDevice(id, lock) {
        postAction(id, lock ? "lock" : "unlock", "{}")
    }

    function setVolume(id, val) {
        // optimistic
        const idx = findIndex(id)
        if (idx >= 0) deviceModel.setProperty(idx, "volume", val)
        postAction(id, "volume", JSON.stringify({value: val}))
    }

    function mediaCmd(id, cmd) {
        const idx = findIndex(id)
        if (idx >= 0) {
            const pb = cmd === "play" ? "playing" : (cmd === "pause" ? "paused" : "stopped")
            deviceModel.setProperty(idx, "playback", pb)
        }
        postAction(id, cmd, "{}")
    }

    function setAcMode(id, mode) {
        const idx = findIndex(id)
        if (idx >= 0) deviceModel.setProperty(idx, "acMode", mode)
        postAction(id, "mode", JSON.stringify({value: mode}))
    }

    function setSetpoint(id, val) {
        const idx = findIndex(id)
        if (idx >= 0) deviceModel.setProperty(idx, "setpoint", val)
        postAction(id, "setpoint", JSON.stringify({value: val}))
    }

    function renameChannel(deviceId, outlet, name) {
        const xhr = new XMLHttpRequest()
        xhr.open("POST", daemonUrl + "/channel_name")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE)
                fetchDevices()
        }
        xhr.send(JSON.stringify({ device_id: deviceId, outlet: outlet, name: name }))
    }

    function postAction(id, action, bodyStr) {
        const xhr = new XMLHttpRequest()
        xhr.open("POST", `${daemonUrl}/devices/${id}/${action}`)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE)
                fetchDevices()
        }
        xhr.send(bodyStr || "{}")
    }
}
