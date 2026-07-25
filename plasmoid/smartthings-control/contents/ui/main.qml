import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string daemonUrl: "http://127.0.0.1:7182"
    // Poll fast while the popup is open; the daemon itself only reaches the
    // cloud every 20 s, so polling faster than this buys nothing but wakeups.
    readonly property int pollFastMs: 4000
    readonly property int pollSlowMs: 30000

    // Palette: dark surface, teal ink/structure, coral for active/alert states,
    // cream for secondary text.
    readonly property color darkBg:      "#1C1C1C"
    readonly property color creamColor:  "#F2E8D1"
    readonly property color tealColor:   "#3DA0AB"
    readonly property color coralColor:  "#DD664E"
    // One colour per function, same vocabulary as DeviceCard.qml:
    readonly property color popupColor:  darkBg      // popup ground
    readonly property color structColor: tealColor   // borders, chrome, headers
    readonly property color secondColor: "#9C978B"   // secondary text (5.9:1 on the popup)
    readonly property color stateColor:  coralColor  // on / alert
    readonly property color structDim:   "#803DA0AB" // structure, receded (50 % teal)

    // Type scale derived from the Plasma font settings, so the widget follows
    // the desktop's font size and HiDPI scaling instead of fixed pixel sizes.
    // A font defined in points reports pixelSize -1, hence the gridUnit fallback
    // (gridUnit is the cap height of the default font, so it scales the same).
    readonly property int fontM:  Kirigami.Theme.defaultFont.pixelSize > 0
                                  ? Kirigami.Theme.defaultFont.pixelSize
                                  : Math.round(Kirigami.Units.gridUnit * 0.62)
    readonly property int fontXS: Math.max(7, Math.round(fontM * 0.72))
    readonly property int fontS:  Math.max(8, Math.round(fontM * 0.85))
    readonly property int fontL:  Math.round(fontM * 1.8)

    // Tiles are 4:3 (see DeviceCard), so the minimum width also sets the height
    // budget: icon plus a name plus one secondary line.
    readonly property int tileMinWidth: Kirigami.Units.gridUnit * 5

    property int activeTab: 0
    property string searchText: ""
    property string roomFilter: ""      // "" = every room
    readonly property var tabDefs: [
        { label: "Luces",      types: ["switch", "dimmer"] },
        // Hidden automatically while you own no locks (see tabCounts).
        { label: "Cerraduras", types: ["lock"] },
        { label: "Clima",      types: ["ac"] },
        { label: "Multimedia", types: ["tv", "speaker"] },
        { label: "Aparatos",   types: ["appliance"] },
        { label: "Sensores",   types: ["sensor"] },
        { label: "Botones",    types: ["button"] },
        { label: "Hubs",       types: ["hub"] },
    ]

    preferredRepresentation: compactRepresentation
    toolTipMainText: "SmartThings Control"
    toolTipSubText: {
        if (!daemonOk) return "Daemon offline"
        if (!everLoaded) return "Cargando…"
        return activeCount > 0 ? `${deviceModel.count} dispositivos · ${activeCount} encendidos`
                               : `${deviceModel.count} dispositivos`
    }

    // ── Compact (panel icon) ──────────────────────────────────────────────────
    compactRepresentation: Item {
        Kirigami.Icon {
            id: compactIcon
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            source: root.daemonOk ? Qt.resolvedUrl("../icons/smartthings.svg") : "network-offline"
            isMask: root.daemonOk
            color: root.activeCount > 0 ? root.stateColor : Kirigami.Theme.textColor
            opacity: root.daemonOk ? 1 : 0.5
        }

        // Badge: how many devices are currently on, at a glance from the panel.
        Rectangle {
            visible: root.daemonOk && root.activeCount > 0
            anchors.right:  compactIcon.right
            anchors.bottom: compactIcon.bottom
            width:  Math.max(badgeLabel.implicitWidth + 4, height)
            height: Math.round(compactIcon.height * 0.45)
            radius: height / 2
            color: root.stateColor

            Text {
                id: badgeLabel
                anchors.centerIn: parent
                text: root.activeCount
                color: root.darkBg
                font.bold: true
                font.family: "monospace"
                font.pixelSize: Math.max(7, Math.round(parent.height * 0.8))
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.MiddleButton)
                    root.refreshNow()
                else
                    root.expanded = !root.expanded
            }
        }
    }

    // ── Full (popup) ──────────────────────────────────────────────────────────
    fullRepresentation: Item {
        implicitWidth:  Kirigami.Units.gridUnit * 30
        implicitHeight: Kirigami.Units.gridUnit * 24
        Layout.preferredWidth:  Kirigami.Units.gridUnit * 30
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24
        Layout.minimumWidth:    Kirigami.Units.gridUnit * 22

        Rectangle {
            anchors.fill: parent
            color: root.popupColor

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing * 2
                spacing: Kirigami.Units.smallSpacing

                // ── Header ────────────────────────────────────────────────────
                // One line: the decorative second line and the oversized wordmark
                // were costing a row of devices in a 432 px popup.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Text {
                        text: "SMARTTHINGS"
                        font.bold: true
                        font.pixelSize: Math.round(root.fontM * 1.15)
                        font.family: "monospace"
                        font.letterSpacing: 1.6
                        color: root.structColor
                    }

                    Rectangle {
                        implicitWidth: 5; implicitHeight: 5; radius: 3
                        color: root.daemonOk ? root.structColor : root.stateColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: !root.daemonOk
                        text: "DAEMON OFFLINE"
                        font.pixelSize: root.fontXS
                        font.bold: true
                        font.family: "monospace"
                        color: root.stateColor
                    }

                    Text {
                        visible: root.daemonOk
                        text: root.activeCount > 0 ? `${deviceModel.count} · ${root.activeCount} ON`
                                                   : `${deviceModel.count}`
                        font.pixelSize: root.fontXS
                        font.family: "monospace"
                        color: root.secondColor
                    }

                    Rectangle {
                        implicitWidth:  Kirigami.Units.gridUnit * 1.35
                        implicitHeight: Kirigami.Units.gridUnit * 1.35
                        color: (refreshArea.containsMouse && !root.refreshing)
                               ? root.structColor : "transparent"
                        border.color: root.structColor
                        border.width: 1

                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.refreshing
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refreshNow()
                            QQC2.ToolTip.text: root.refreshing ? "Consultando SmartThings…"
                                                               : "Actualizar desde SmartThings"
                            QQC2.ToolTip.visible: containsMouse

                            Text {
                                id: refreshGlyph
                                anchors.centerIn: parent
                                text: "↺"
                                font.pixelSize: root.fontM + 2
                                font.bold: true
                                color: (refreshArea.containsMouse && !root.refreshing)
                                       ? root.popupColor : root.structColor

                                RotationAnimation on rotation {
                                    running: root.refreshing
                                    from: 0; to: 360
                                    duration: 1400
                                    loops: Animation.Infinite
                                    onStopped: refreshGlyph.rotation = 0
                                }
                            }
                        }
                    }
                }

                // ── Divider ───────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.structColor
                    opacity: 0.3
                }

                // ── Search + room filter ──────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Buscar dispositivo…"
                        font.family: "monospace"
                        font.pixelSize: root.fontS
                        text: root.searchText
                        onTextChanged: root.searchText = text
                        Keys.onEscapePressed: { text = ""; root.searchText = "" }
                    }

                    QQC2.ComboBox {
                        id: roomBox
                        visible: root.roomList.length > 1
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                        font.family: "monospace"
                        font.pixelSize: root.fontS
                        model: ["Todas"].concat(root.roomList)
                        onActivated: root.roomFilter = (currentIndex === 0 ? "" : currentText)
                        // Reset if the selected room disappears from the model.
                        onModelChanged: if (currentIndex >= model.length) currentIndex = 0
                    }
                }

                // ── Tab bar ───────────────────────────────────────────────────
                // A single scrollable row instead of a wrapping Flow: seven tabs
                // always wrapped to two rows, which cost ~24 px of device list.
                ListView {
                    id: tabBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(root.fontS * 2.2)
                    orientation: ListView.Horizontal
                    spacing: 3
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.visibleTabs

                    delegate: Rectangle {
                        required property int modelData      // index into tabDefs

                        readonly property bool active: root.activeTab === modelData
                        readonly property int  count:  root.tabCounts[modelData] || 0

                        width: tabLabel.implicitWidth + Kirigami.Units.gridUnit
                        height: tabBar.height
                        color: active ? root.structColor : "transparent"
                        border.color: active ? root.structColor : root.structDim
                        border.width: 1

                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: root.tabDefs[parent.modelData].label.toUpperCase()
                                  + "  " + parent.count
                            font.bold: true
                            font.pixelSize: root.fontXS
                            font.family: "monospace"
                            font.letterSpacing: 1
                            color: parent.active ? root.popupColor : root.secondColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeTab = parent.modelData
                        }
                    }

                    // Keep the selected tab on screen when the row overflows.
                    Connections {
                        target: root
                        function onActiveTabChanged() {
                            const i = root.visibleTabs.indexOf(root.activeTab)
                            if (i >= 0) tabBar.positionViewAtIndex(i, ListView.Contain)
                        }
                    }

                    // Fade at each end, so a clipped chip reads as "there is more"
                    // rather than as a rendering glitch.
                    Rectangle {
                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                        width: Kirigami.Units.gridUnit
                        visible: tabBar.contentX + tabBar.width < tabBar.contentWidth - 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: root.popupColor }
                        }
                    }

                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: Kirigami.Units.gridUnit
                        visible: tabBar.contentX > 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: root.popupColor }
                            GradientStop { position: 1.0; color: "transparent" }
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

                            // Columns come from a minimum tile size, so tiles stay
                            // legible when the widget is resized or on HiDPI.
                            readonly property int tileColumns:
                                Math.max(2, Math.floor((width + spacing) / (root.tileMinWidth + spacing)))

                            Repeater {
                                model: deviceModel

                                DeviceCard {
                                    tile: deviceType === "switch" || deviceType === "lock"
                                    visible: root.matchesFilters(modelKey, deviceType,
                                                                 deviceName, groupName, roomName,
                                                                 root.activeTab)
                                    width: tile
                                        ? Math.floor((deviceFlow.width
                                                      - deviceFlow.spacing * (deviceFlow.tileColumns - 1))
                                                     / deviceFlow.tileColumns)
                                        : deviceFlow.width
                                    onToggleRequested:    (id, out) => toggleDevice(id, out)
                                    onBrightnessSet:      (id, val) => setBrightness(id, val)
                                    onRenameRequested:    (key, name) => renameDevice(key, name)
                                    onLockRequested:      (id, lock) => lockDevice(id, lock)
                                    onVolumeSet:          (id, val) => setVolume(id, val)
                                    onPlaybackRequested:  (id, cmd) => mediaCmd(id, cmd)
                                    onAcModeSet:          (id, mode) => setAcMode(id, mode)
                                    onSetpointSet:        (id, val) => setSetpoint(id, val)
                                }
                            }
                        }

                        // ── Empty / loading / offline states ──────────────────
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.gridUnit
                            spacing: Kirigami.Units.smallSpacing
                            visible: root.emptyState !== ""

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                opacity: 0.55
                                text: root.emptyState
                                font.family: "monospace"
                                font.pixelSize: root.fontS
                                color: root.emptyState.indexOf("OFFLINE") >= 0 ? root.stateColor
                                                                               : root.structColor
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                visible: !root.daemonOk
                                implicitWidth:  retryLabel.implicitWidth + Kirigami.Units.gridUnit
                                implicitHeight: Math.round(root.fontS * 2.4)
                                color: "transparent"
                                border.color: root.stateColor
                                border.width: 1

                                Text {
                                    id: retryLabel
                                    anchors.centerIn: parent
                                    text: "REINTENTAR"
                                    font.family: "monospace"
                                    font.bold: true
                                    font.pixelSize: root.fontXS
                                    color: root.stateColor
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.fetchDevices()
                                }
                            }
                        }
                    }
                }

                // ── Error banner ──────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.errorMsg !== ""
                    implicitHeight: Math.round(root.fontS * 2.4)
                    color: root.stateColor

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.rightMargin: Kirigami.Units.smallSpacing

                        Text {
                            Layout.fillWidth: true
                            text: root.errorMsg
                            elide: Text.ElideRight
                            font.family: "monospace"
                            font.bold: true
                            font.pixelSize: root.fontXS
                            color: root.darkBg
                        }
                        Text {
                            text: "✕"
                            font.pixelSize: root.fontS
                            color: root.darkBg
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.errorMsg = ""
                            }
                        }
                    }
                }

                // ── Footer ────────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.structColor
                    opacity: 0.3
                }

                // The counts moved to the header, so the footer is just freshness.
                Text {
                    Layout.fillWidth: true
                    text: root.lastUpdateText
                    font.pixelSize: root.fontXS
                    font.family: "monospace"
                    color: root.secondColor
                    opacity: 0.7
                }
            }
        }
    }

    // ── Data model ────────────────────────────────────────────────────────────
    ListModel { id: deviceModel }

    property bool daemonOk: false
    property bool everLoaded: false          // a first successful fetch has landed
    property bool refreshing: false          // a forced cloud sweep is in flight
    property string errorMsg: ""
    // When the *daemon* last read the cloud — not when we last read its cache.
    property double lastUpdate: 0
    property int nowTick: 0                  // drives the relative "hace Ns" label
    // Bumped on every model rebuild: ListModel changes don't invalidate bindings
    // on their own, so anything derived from the model depends on this instead.
    property int modelRevision: 0

    // ── Derived state ─────────────────────────────────────────────────────────

    readonly property var roomList: {
        modelRevision                       // dependency
        var seen = ({}), out = []
        for (var i = 0; i < deviceModel.count; i++) {
            var r = deviceModel.get(i).roomName
            if (r && !seen[r]) { seen[r] = true; out.push(r) }
        }
        out.sort()
        return out
    }

    // Tabs worth showing: those with results, plus the current one so the bar
    // never jumps out from under the selection.
    readonly property var visibleTabs: {
        modelRevision; searchText; roomFilter; activeTab   // dependencies
        var out = []
        for (var t = 0; t < tabDefs.length; t++)
            if ((tabCounts[t] || 0) > 0 || activeTab === t) out.push(t)
        return out
    }

    readonly property var tabCounts: {
        modelRevision; searchText; roomFilter   // dependencies
        var counts = []
        for (var t = 0; t < tabDefs.length; t++) {
            var n = 0
            for (var i = 0; i < deviceModel.count; i++) {
                var it = deviceModel.get(i)
                if (matchesFilters(it.modelKey, it.deviceType, it.deviceName,
                                   it.groupName, it.roomName, t)) n++
            }
            counts.push(n)
        }
        return counts
    }

    readonly property int activeCount: {
        modelRevision
        var n = 0
        for (var i = 0; i < deviceModel.count; i++) {
            var it = deviceModel.get(i)
            if (it.switchOn && ["switch", "dimmer", "tv", "ac", "appliance"].indexOf(it.deviceType) >= 0)
                n++
        }
        return n
    }

    readonly property string emptyState: {
        if (!daemonOk)                        return "// DAEMON OFFLINE //"
        if (!everLoaded)                      return "// CARGANDO... //"
        if (deviceModel.count === 0)          return "// SIN DISPOSITIVOS //"
        if ((tabCounts[activeTab] || 0) > 0)  return ""
        if (searchText !== "" || roomFilter !== "") return "// SIN RESULTADOS //"
        return "// SIN DISPOSITIVOS //"
    }

    readonly property string lastUpdateText: {
        nowTick                               // dependency
        if (refreshing)       return "CONSULTANDO SMARTTHINGS…"
        if (lastUpdate === 0) return ""
        var secs = Math.round((Date.now() - lastUpdate) / 1000)
        if (secs < 5)  return "ACTUALIZADO AHORA"
        if (secs < 60) return "ACTUALIZADO HACE " + secs + "S"
        return "ACTUALIZADO HACE " + Math.round(secs / 60) + "M"
    }

    function matchesFilters(key, type, name, group, room, tabIndex) {
        if (tabDefs[tabIndex].types.indexOf(type) < 0) return false
        if (roomFilter !== "" && room !== roomFilter)  return false
        if (searchText === "") return true
        var q = searchText.toLowerCase()
        return name.toLowerCase().indexOf(q) >= 0
            || group.toLowerCase().indexOf(q) >= 0
            || room.toLowerCase().indexOf(q) >= 0
    }

    // Keep the user on a tab that actually has results.
    function ensureUsefulTab() {
        if ((tabCounts[activeTab] || 0) > 0) return
        for (var t = 0; t < tabDefs.length; t++) {
            if ((tabCounts[t] || 0) > 0) { activeTab = t; return }
        }
    }

    onSearchTextChanged: ensureUsefulTab()
    onRoomFilterChanged: ensureUsefulTab()
    onExpandedChanged: if (expanded) fetchDevices()

    // ── Timers ────────────────────────────────────────────────────────────────
    Timer {
        id: pollTimer
        interval: root.expanded ? root.pollFastMs : root.pollSlowMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchDevices()
    }

    Timer {   // relative-time label, only while the popup is visible
        interval: 5000
        running: root.expanded
        repeat: true
        onTriggered: root.nowTick++
    }

    Timer {
        id: errorTimer
        interval: 6000
        onTriggered: root.errorMsg = ""
    }

    function showError(msg) {
        errorMsg = msg
        errorTimer.restart()
    }

    // ── API helpers ───────────────────────────────────────────────────────────

    // Ask the daemon to go out to SmartThings right now. Plain fetchDevices()
    // only re-reads its cache, which is at most POLL_INTERVAL old.
    function refreshNow() {
        if (refreshing) return
        refreshing = true

        const xhr = new XMLHttpRequest()
        xhr.open("POST", daemonUrl + "/refresh")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 45000          // a full sweep is a few seconds
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            refreshing = false
            if (xhr.status !== 200)
                showError("No se pudo actualizar: " + errorDetail(xhr))
            fetchDevices()
        }
        xhr.onerror   = () => { refreshing = false; showError("No se pudo actualizar: daemon sin respuesta") }
        xhr.ontimeout = () => { refreshing = false; showError("La actualización tardó demasiado") }
        xhr.send("{}")
    }

    function fetchDevices() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", daemonUrl + "/devices")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                daemonOk = true
                everLoaded = true
                // Freshness comes from the daemon's own cloud read; falling back
                // to "now" would claim the data is newer than it is.
                const stamp = parseFloat(xhr.getResponseHeader("X-Last-Refresh") || "0")
                lastUpdate = stamp > 0 ? stamp * 1000 : 0
                nowTick++
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
                        origName:     "Canal " + (i + 1),
                        hasAlias:     !!chNames[i],
                        deviceType:   "switch",
                        deviceOnline: d.online,
                        roomName:     d.room || "",
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

        sortModel()
        modelRevision++
        if (roomFilter !== "" && roomList.indexOf(roomFilter) < 0)
            roomFilter = ""          // the filtered room is gone; show everything
        ensureUsefulTab()
    }

    function flatDevice(d) {
        const s = d.state || {}
        return {
            modelKey:     d.id,
            deviceId:     d.id,
            deviceName:   d.name,
            origName:     d.orig_name ?? d.name,
            hasAlias:     !!d.orig_name,
            deviceType:   d.type,
            deviceOnline: d.online,
            roomName:     d.room ?? "",
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

    // Order by room, then by device (channels of one strip stay together), so
    // the grid reads as rooms even though it is a single flow.
    function sortModel() {
        const items = []
        for (let i = 0; i < deviceModel.count; i++) {
            const it = deviceModel.get(i)
            items.push({
                key:  it.modelKey,
                // Devices with no room sink to the bottom.
                sort: (it.roomName || "￿").toLowerCase() + " "
                    + (it.groupName || it.deviceName).toLowerCase() + " "
                    + it.deviceName.toLowerCase(),
            })
        }
        items.sort((a, b) => a.sort < b.sort ? -1 : (a.sort > b.sort ? 1 : 0))
        for (let target = 0; target < items.length; target++) {
            const cur = findIndex(items[target].key)
            if (cur >= 0 && cur !== target)
                deviceModel.move(cur, target, 1)
        }
    }

    function findIndex(key) {
        for (let i = 0; i < deviceModel.count; i++)
            if (deviceModel.get(i).modelKey === key) return i
        return -1
    }

    function deviceLabel(key) {
        const idx = findIndex(key)
        return idx >= 0 ? deviceModel.get(idx).deviceName : "dispositivo"
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
        postAction(id, "toggle", body, key)
    }

    function setBrightness(id, val) {
        postAction(id, "brightness", JSON.stringify({value: val}), id)
    }

    function lockDevice(id, lock) {
        postAction(id, lock ? "lock" : "unlock", "{}", id)
    }

    function setVolume(id, val) {
        // optimistic
        const idx = findIndex(id)
        if (idx >= 0) deviceModel.setProperty(idx, "volume", val)
        postAction(id, "volume", JSON.stringify({value: val}), id)
    }

    function mediaCmd(id, cmd) {
        const idx = findIndex(id)
        if (idx >= 0) {
            const pb = cmd === "play" ? "playing" : (cmd === "pause" ? "paused" : "stopped")
            deviceModel.setProperty(idx, "playback", pb)
        }
        postAction(id, cmd, "{}", id)
    }

    function setAcMode(id, mode) {
        const idx = findIndex(id)
        if (idx >= 0) deviceModel.setProperty(idx, "acMode", mode)
        postAction(id, "mode", JSON.stringify({value: mode}), id)
    }

    function setSetpoint(id, val) {
        const idx = findIndex(id)
        if (idx >= 0) deviceModel.setProperty(idx, "setpoint", val)
        postAction(id, "setpoint", JSON.stringify({value: val}), id)
    }

    // Local-only rename: stored by the daemon, never pushed to SmartThings.
    // An empty name restores the original cloud name.
    function renameDevice(key, name) {
        const idx = findIndex(key)
        if (idx >= 0 && name)
            deviceModel.setProperty(idx, "deviceName", name)  // optimistic

        const xhr = new XMLHttpRequest()
        xhr.open("POST", daemonUrl + "/alias")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200)
                showError("No se pudo renombrar")
            fetchDevices()
        }
        xhr.onerror   = () => showError("No se pudo renombrar: daemon sin respuesta")
        xhr.ontimeout = () => showError("No se pudo renombrar: sin respuesta")
        xhr.send(JSON.stringify({ key: key, name: name }))
    }

    function postAction(id, action, bodyStr, modelKey) {
        const label = deviceLabel(modelKey || id)
        const xhr = new XMLHttpRequest()
        xhr.open("POST", `${daemonUrl}/devices/${id}/${action}`)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            // A failed command leaves the optimistic state on screen until the
            // next poll corrects it — say so instead of letting it bounce back
            // silently a few seconds later.
            if (xhr.status !== 200)
                showError(`Falló «${label}»: ` + errorDetail(xhr))
            fetchDevices()
        }
        xhr.onerror   = () => { showError(`Falló «${label}»: daemon sin respuesta`); fetchDevices() }
        xhr.ontimeout = () => { showError(`Falló «${label}»: sin respuesta`); fetchDevices() }
        xhr.send(bodyStr || "{}")
    }

    function errorDetail(xhr) {
        try {
            const data = JSON.parse(xhr.responseText)
            if (data.error) return String(data.error).slice(0, 80)
        } catch (e) { /* not JSON */ }
        return "error " + xhr.status
    }
}
