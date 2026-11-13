import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

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
        // Not a device type: the daemon's event log. Always shown, last.
        { label: "Historial",  types: [], history: true },
    ]
    readonly property int historyTab: tabDefs.length - 1
    readonly property bool historyActive: activeTab === historyTab

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
                        // Filled while the mode is on: it is a state you can
                        // leave the widget in, so it has to look switched on.
                        color: (root.reordering || reorderArea.containsMouse)
                               ? root.structColor : "transparent"
                        border.color: root.structColor
                        border.width: 1

                        MouseArea {
                            id: reorderArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.reordering = !root.reordering
                            QQC2.ToolTip.text: root.reordering ? "Salir de reordenar"
                                                               : "Reordenar dispositivos"
                            QQC2.ToolTip.visible: containsMouse

                            Text {
                                anchors.centerIn: parent
                                text: "⇅"
                                font.pixelSize: root.fontM + 2
                                font.bold: true
                                color: (root.reordering || reorderArea.containsMouse)
                                       ? root.popupColor : root.structColor
                            }
                        }
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
                        placeholderText: root.historyActive ? "Buscar en el historial…"
                                                            : "Buscar dispositivo…"
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
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(root.fontS * 2.2)

                    ListView {
                        id: tabBar
                        anchors.fill: parent
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
                                color: parent.active ? root.popupColor
                                     : (parent.modelData === root.historyTab && parent.count > 0)
                                       ? root.stateColor : root.secondColor
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

                    }

                    // Fade at each end, so a clipped chip reads as "there is more"
                    // rather than as a rendering glitch. Siblings of the view, not
                    // children: inline children of a ListView are reparented to its
                    // contentItem, which would scroll them away with the chips.
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

                // ── Reorder banner ────────────────────────────────────────────
                // The mode swallows every control on a card, so it has to say so
                // plainly and offer the way out; nothing else explains why a tap
                // on a light stopped turning it on.
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.reordering
                    implicitHeight: Math.round(root.fontS * 2.6)
                    color: "transparent"
                    border.color: root.structColor
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin:  Kirigami.Units.smallSpacing
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Text {
                            Layout.fillWidth: true
                            text: "REORDENANDO · ARRASTRA LAS TARJETAS"
                            elide: Text.ElideRight
                            font.family: "monospace"
                            font.bold: true
                            font.pixelSize: root.fontXS
                            color: root.structColor
                        }

                        PanelButton {
                            label: "RESTABLECER"
                            visible: root.customOrder.length > 0
                            onClicked: root.resetOrder()
                        }
                        PanelButton {
                            label: "LISTO"
                            onClicked: root.reordering = false
                        }
                    }
                }

                // ── Device list ───────────────────────────────────────────────
                QQC2.ScrollView {
                    id: scrollView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // Wheel turns that a slider swallowed are handed back here, so
                    // the list still scrolls when the cursor sits on a volume bar.
                    // 120 angle units is one notch; three lines each, as elsewhere.
                    function scrollBy(delta) {
                        const flick = contentItem
                        const max = Math.max(0, flick.contentHeight - flick.height)
                        flick.contentY = Math.max(0, Math.min(max,
                            flick.contentY - (delta / 120) * Kirigami.Units.gridUnit * 3))
                    }

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
                                          || deviceType === "button"
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
                                    onMachineRequested:   (id, st) => setMachine(id, st)
                                    onTvCommand:          (id, act, val) => tvCmd(id, act, val)
                                    watchtvAvailable:     root.watchtvPath !== ""
                                    onSendToTvRequested:  (name) => root.launchWatchtv(name)
                                    onScrollRequested:    (delta) => scrollView.scrollBy(delta)
                                    onCopyRequested:      (text) => copyToClipboard(text, "COPIADO AL PORTAPAPELES")
                                    onInfoRequested:      (title, body) => infoPanel.show(title, body)
                                    onHistoryRequested:   (id) => root.openHistory(id)
                                    reordering: root.reordering
                                    onReorderDragged:     (key, sx, sy) => {
                                        // Scene coordinates, so the card under
                                        // the pointer is found even once the
                                        // pointer has left the dragged card.
                                        const p = deviceFlow.mapFromItem(null, sx, sy)
                                        const under = deviceFlow.childAt(p.x, p.y)
                                        reorderTo(key, under && under.modelKey !== undefined
                                                       ? under.modelKey : "")
                                    }
                                    onReorderDropped:     () => saveOrder()
                                }
                            }
                        }

                        // ── History ───────────────────────────────────────────
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.historyActive && root.daemonOk
                            spacing: Kirigami.Units.smallSpacing

                            // Filters and actions, one row.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                PanelButton {
                                    label: "TODO"
                                    active: !root.historyOnlyIssues
                                    onClicked: root.historyOnlyIssues = false
                                }
                                PanelButton {
                                    label: "SOLO FALLOS"
                                    active: root.historyOnlyIssues
                                    tint: root.stateColor
                                    onClicked: root.historyOnlyIssues = true
                                }
                                // The device filter, as a removable chip.
                                PanelButton {
                                    visible: root.historyDevice !== ""
                                    label: "✕ " + root.historyDeviceName.toUpperCase()
                                    active: true
                                    Layout.maximumWidth: Kirigami.Units.gridUnit * 9
                                    onClicked: root.historyDevice = ""
                                }

                                Item { Layout.fillWidth: true }

                                PanelButton {
                                    label: "COPIAR"
                                    visible: root.filteredEvents.length > 0
                                    onClicked: root.copyToClipboard(root.historyReport(),
                                                                    "HISTORIAL COPIADO")
                                }
                                // Two steps: wiping the history is the one thing
                                // here that cannot be undone.
                                PanelButton {
                                    label: root.confirmingClear ? "¿BORRAR TODO?" : "LIMPIAR"
                                    tint: root.stateColor
                                    active: root.confirmingClear
                                    onClicked: {
                                        if (root.confirmingClear) {
                                            root.confirmingClear = false
                                            root.clearHistory()
                                        } else {
                                            root.confirmingClear = true
                                            clearConfirmTimer.restart()
                                        }
                                    }
                                    Timer {
                                        id: clearConfirmTimer
                                        interval: 4000
                                        onTriggered: root.confirmingClear = false
                                    }
                                }
                            }

                            // Which devices are sick, worst first. A chip filters
                            // the list to that device — the usual next question.
                            Text {
                                visible: root.issueDevices.length > 0 && root.historyDevice === ""
                                text: "CON INCIDENCIAS · 24 H"
                                font.family: "monospace"
                                font.bold: true
                                font.pixelSize: root.fontXS
                                font.letterSpacing: 1
                                color: root.secondColor
                            }

                            Flow {
                                Layout.fillWidth: true
                                visible: root.issueDevices.length > 0 && root.historyDevice === ""
                                spacing: 4

                                Repeater {
                                    model: root.issueDevices

                                    Rectangle {
                                        required property var modelData
                                        width:  chipRow.implicitWidth + Kirigami.Units.smallSpacing * 3
                                        height: Math.round(root.fontS * 2.3)
                                        color: chipArea.containsMouse ? "#2E2320" : "#2A2A2A"
                                        border.color: modelData.errors > 0 ? root.stateColor : root.structDim
                                        border.width: 1

                                        Row {
                                            id: chipRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                text: parent.parent.modelData.device_name || "Daemon"
                                                font.bold: true
                                                font.pixelSize: root.fontS
                                                color: root.creamColor
                                            }
                                            Text {
                                                readonly property string room:
                                                    root.roomById[parent.parent.modelData.device_id] || ""
                                                visible: room !== ""
                                                text: room.toUpperCase()
                                                font.family: "monospace"
                                                font.pixelSize: root.fontXS
                                                color: root.secondColor
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                visible: parent.parent.modelData.errors > 0
                                                text: "✕" + parent.parent.modelData.errors
                                                font.family: "monospace"
                                                font.bold: true
                                                font.pixelSize: root.fontXS
                                                color: root.stateColor
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                visible: parent.parent.modelData.warnings > 0
                                                text: "!" + parent.parent.modelData.warnings
                                                font.family: "monospace"
                                                font.bold: true
                                                font.pixelSize: root.fontXS
                                                color: root.secondColor
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                        MouseArea {
                                            id: chipArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.historyDevice =
                                                parent.modelData.device_id || "_daemon"
                                            QQC2.ToolTip.text: parent.modelData.last_message
                                            QQC2.ToolTip.visible: containsMouse
                                        }
                                    }
                                }
                            }

                            Repeater {
                                model: root.filteredEvents
                                EventRow {}
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.gridUnit
                                visible: root.filteredEvents.length === 0
                                horizontalAlignment: Text.AlignHCenter
                                opacity: 0.55
                                text: !root.eventsLoaded ? "// CARGANDO... //"
                                    : root.historyOnlyIssues ? "// SIN FALLOS //"
                                    : "// SIN EVENTOS //"
                                font.family: "monospace"
                                font.pixelSize: root.fontS
                                color: root.structColor
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

                // The counts moved to the header, so the footer is just freshness
                // — and the one place a copy can report itself without a dialog.
                Text {
                    Layout.fillWidth: true
                    text: root.flashMsg !== "" ? root.flashMsg : root.lastUpdateText
                    font.pixelSize: root.fontXS
                    font.family: "monospace"
                    color: root.secondColor
                    opacity: 0.7
                }
            }
        }

        QQC2.Popup {
            id: infoPanel

            property string deviceTitle: ""
            property string body: ""

            function show(title, text) {
                deviceTitle = title
                body        = text
                open()
            }

            Component.onCompleted: infoPanelProxy.panel = infoPanel

            // Declared inside the full representation on purpose: that is the
            // item that gets reparented into the popup window, so this is the
            // window the panel opens in. Hung off the applet root instead, it
            // belonged to the panel's window and never showed. Its parent is
            // therefore the popup itself, which is also what it centres on —
            // no Overlay lookup, which is null this early in a plasmoid.
            anchors.centerIn: parent
            width: Math.min(parent ? parent.width - Kirigami.Units.gridUnit * 2 : 400,
                            Kirigami.Units.gridUnit * 26)
            modal: true
            focus: true
            padding: Kirigami.Units.smallSpacing * 2
            closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

            background: Rectangle {
                color: root.popupColor
                border.color: root.structColor
                border.width: 1
            }

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                Text {
                    Layout.fillWidth: true
                    text: infoPanel.deviceTitle
                    elide: Text.ElideRight
                    font.bold: true
                    font.pixelSize: root.fontS
                    color: root.creamColor
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: root.structColor
                    opacity: 0.4
                }

                // Read-only but selectable, so a single value can be dragged out
                // without taking the whole block.
                TextEdit {
                    Layout.fillWidth: true
                    readOnly: true
                    selectByMouse: true
                    text: infoPanel.body
                    font.family: "monospace"
                    font.pixelSize: root.fontXS
                    color: root.creamColor
                    selectionColor: root.structColor
                    selectedTextColor: root.popupColor
                    // Identity lines are short; an event's raw cloud error is
                    // not, and must stay readable rather than run off the edge.
                    wrapMode: Text.WrapAnywhere
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Item { Layout.fillWidth: true }

                    PanelButton {
                        label: "COPIAR"
                        onClicked: root.copyToClipboard(
                            infoPanel.deviceTitle + "\n" + infoPanel.body,
                            "COPIADO AL PORTAPAPELES")
                    }
                    PanelButton {
                        label: "CERRAR"
                        onClicked: infoPanel.close()
                    }
                }
            }
        }
    }

    // ── Device fact sheet ─────────────────────────────────────────────────────
    // A tooltip is gone by the time you reach for it, so anything meant to be
    // read twice or picked apart lives here: it stays until dismissed and the
    // text can be selected. It is a popup inside the widget rather than a real
    // window on purpose — a window would take focus, and a plasmoid hides itself
    // the moment it loses focus, taking the panel down with it.
    component PanelButton: Rectangle {
        property alias label: buttonLabel.text
        // Filled while selected, like the tabs: a filter that is on has to look on.
        property bool active: false
        property color tint: root.structColor
        signal clicked

        implicitWidth:  buttonLabel.implicitWidth + Kirigami.Units.gridUnit
        implicitHeight: Math.round(root.fontS * 2.4)
        color: active ? tint : "transparent"
        border.color: tint
        border.width: 1

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - Kirigami.Units.smallSpacing * 2)
            elide: Text.ElideRight
            font.family: "monospace"
            font.bold: true
            font.pixelSize: root.fontXS
            color: parent.active ? root.popupColor : parent.tint
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    // ── History row ───────────────────────────────────────────────────────────
    // Errors get the same treatment as a device that is on — warm ground plus a
    // coral bar — because they are what the eye should land on. Warnings keep
    // the bar but not the ground; plain events are just text, so a quiet day
    // reads as quiet.
    component EventRow: Rectangle {
        required property var modelData
        readonly property bool isError: modelData.level === "error"
        readonly property bool isWarn:  modelData.level === "warn"

        Layout.fillWidth: true
        implicitHeight: rowCol.implicitHeight + Kirigami.Units.smallSpacing * 2
        color: isError ? "#2E2320" : (rowArea.containsMouse ? "#262626" : "transparent")
        border.color: root.structColor
        border.width: rowArea.containsMouse ? 1 : 0

        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 3
            visible: parent.isError || parent.isWarn
            color: root.stateColor
            opacity: parent.isError ? 1 : 0.5
        }

        ColumnLayout {
            id: rowCol
            anchors {
                left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                leftMargin: Kirigami.Units.smallSpacing * 2 + 3
                rightMargin: Kirigami.Units.smallSpacing * 2
            }
            spacing: 1

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Text {
                    text: root.formatTime(modelData.last_ts)
                    font.family: "monospace"
                    font.pixelSize: root.fontXS
                    color: root.secondColor
                }
                Text {
                    // Takes what it needs up to 60 %; the room gets the rest.
                    Layout.maximumWidth: Math.round(rowCol.width * 0.6)
                    text: modelData.device_name || "Daemon"
                    elide: Text.ElideRight
                    font.bold: true
                    font.pixelSize: root.fontS
                    color: root.creamColor
                }
                // Names repeat ("Motion Sensor" twice); the room tells them apart.
                Text {
                    Layout.fillWidth: true
                    text: (root.roomById[modelData.device_id] || "").toUpperCase()
                    elide: Text.ElideRight
                    font.family: "monospace"
                    font.pixelSize: root.fontXS
                    color: root.secondColor
                }
                Text {
                    visible: modelData.count > 1
                    text: "×" + modelData.count + " · desde " + root.formatTime(modelData.ts)
                    font.family: "monospace"
                    font.pixelSize: root.fontXS
                    color: isError ? root.stateColor : root.secondColor
                }
            }
            Text {
                Layout.fillWidth: true
                text: modelData.message
                wrapMode: Text.Wrap
                font.family: "monospace"
                font.pixelSize: root.fontXS
                color: (isError || isWarn) ? root.stateColor : root.secondColor
            }
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: infoPanelProxy.show(modelData)
        }
    }

    // EventRow lives at the root but the info panel lives inside the full
    // representation, whose ids are out of scope here (see reorderTo). The panel
    // registers itself on this object when it is created.
    QtObject {
        id: infoPanelProxy
        property var panel: null
        function show(ev) {
            if (panel) panel.show(ev.device_name || "Daemon", root.eventDetail(ev))
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
    property string flashMsg: ""             // transient footer note, e.g. a copy
    // Manual card order: the keys the user dragged, in order. Empty means the
    // default room-then-name sort is in charge.
    property var customOrder: []
    property bool reordering: false
    property bool orderDirty: false          // a drag moved something since the drop
    // Where watchtv-gui is installed ("" = not installed), as the daemon found
    // it. watchtv sends movies to a TV; see daemon/watchtv_bridge.py.
    property string watchtvPath: ""

    // History (the daemon's event log). Fetched only while that tab is open.
    property var events: []
    property var eventSummary: ({})
    property bool eventsLoaded: false
    property bool historyOnlyIssues: false
    property string historyDevice: ""        // device id, "_daemon", or "" for all
    property bool confirmingClear: false

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

    // deviceId → room, for filtering history rows by the room selector.
    readonly property var roomById: {
        modelRevision
        var out = ({})
        for (var i = 0; i < deviceModel.count; i++) {
            var it = deviceModel.get(i)
            out[it.deviceId] = it.roomName
        }
        return out
    }

    // Warnings + errors in 24 h across all devices; a multi-switch appears once
    // per channel in the model, so count each device id once.
    readonly property int issuesTotal: {
        modelRevision
        var seen = ({}), n = 0
        for (var i = 0; i < deviceModel.count; i++) {
            var it = deviceModel.get(i)
            if (seen[it.deviceId]) continue
            seen[it.deviceId] = true
            n += it.issues
        }
        return n
    }

    readonly property var issueDevices: {
        var rows = Object.keys(eventSummary).map(k => eventSummary[k])
        rows.sort((a, b) => (b.errors - a.errors) || (b.warnings - a.warnings)
                            || (b.last_ts - a.last_ts))
        return rows
    }

    readonly property string historyDeviceName: {
        if (historyDevice === "") return ""
        if (historyDevice === "_daemon") return "Daemon"
        for (var i = 0; i < events.length; i++)
            if (events[i].device_id === historyDevice) return events[i].device_name
        var idx = findIndex(historyDevice)
        return idx >= 0 ? deviceModel.get(idx).deviceName : "dispositivo"
    }

    readonly property var filteredEvents: {
        var q = searchText.toLowerCase()
        return events.filter(ev => {
            if (historyOnlyIssues && ev.level === "info") return false
            if (historyDevice === "_daemon" && ev.device_id !== "") return false
            if (historyDevice !== "" && historyDevice !== "_daemon"
                && ev.device_id !== historyDevice) return false
            if (roomFilter !== "" && ev.device_id !== ""
                && roomById[ev.device_id] !== roomFilter) return false
            if (q === "") return true
            return (ev.device_name || "").toLowerCase().indexOf(q) >= 0
                || ev.message.toLowerCase().indexOf(q) >= 0
        })
    }

    // Tabs worth showing: those with results, plus the current one so the bar
    // never jumps out from under the selection.
    //
    // Deliberately not a binding. This depends on activeTab, and a binding would
    // hand the ListView a fresh array on every tab click — a new reference resets
    // the view and destroys every delegate, including the one whose click is
    // still being delivered, so the tab never actually switched. Assigning only
    // when the contents change keeps the model stable across a plain selection.
    property var visibleTabs: []

    function rebuildVisibleTabs() {
        var out = []
        for (var t = 0; t < tabDefs.length; t++)
            if ((tabCounts[t] || 0) > 0 || activeTab === t || tabDefs[t].history) out.push(t)
        if (out.length === visibleTabs.length
            && out.every((v, i) => v === visibleTabs[i])) return
        visibleTabs = out
    }

    onActiveTabChanged: {
        rebuildVisibleTabs()
        if (historyActive) fetchEvents()
    }
    onTabCountsChanged:    rebuildVisibleTabs()
    Component.onCompleted: {
        rebuildVisibleTabs()
        fetchOrder()
        fetchStatus()
    }

    readonly property var tabCounts: {
        modelRevision; searchText; roomFilter   // dependencies
        var counts = []
        for (var t = 0; t < tabDefs.length; t++) {
            var n = 0
            if (tabDefs[t].history) { counts.push(issuesTotal); continue }
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
        if (historyActive)                    return ""   // has its own
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
        if (historyActive) return             // a quiet history is still the tab you chose
        if ((tabCounts[activeTab] || 0) > 0) return
        for (var t = 0; t < tabDefs.length; t++) {
            if (tabDefs[t].history) continue
            if ((tabCounts[t] || 0) > 0) { activeTab = t; return }
        }
    }

    onSearchTextChanged: ensureUsefulTab()
    onRoomFilterChanged: ensureUsefulTab()
    // root.expanded, not the bare name: expandedChanged carries a parameter, and
    // an unqualified `expanded` binds to that injected argument — deprecated in
    // Qt 6 and gone in Qt 7.
    onExpandedChanged: if (root.expanded) { fetchDevices(); fetchStatus() }

    // ── Timers ────────────────────────────────────────────────────────────────
    Timer {
        id: pollTimer
        interval: root.expanded ? root.pollFastMs : root.pollSlowMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.fetchDevices()
            if (root.expanded && root.historyActive) root.fetchEvents()
        }
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

    Timer {
        id: flashTimer
        interval: 3000
        onTriggered: root.flashMsg = ""
    }

    // Qt exposes no clipboard to QML, and the types that do (Clipboard from
    // kquickcontrolsaddons) would add a framework this widget does not otherwise
    // need. A TextEdit's own copy() reaches the same clipboard; it never draws.
    TextEdit {
        id: clipboardRelay
        visible: false
    }

    function copyToClipboard(text, note) {
        clipboardRelay.text = text
        clipboardRelay.selectAll()
        clipboardRelay.copy()
        clipboardRelay.text = ""
        flashMsg = note
        flashTimer.restart()
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
                        // Every channel is the same physical strip, so they all
                        // carry its identity.
                        manufacturer: d.manufacturer || "",
                        model:        d.model        || "",
                        firmware:     d.firmware     || "",
                        integration:  d.integration  || "",
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
                        appliance:    "",
                        media:        "",
                        issues:       d.issues ?? 0,
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
            // Hardware identity, for the tooltip that names a failing device.
            manufacturer: d.manufacturer ?? "",
            model:        d.model        ?? "",
            firmware:     d.firmware     ?? "",
            integration:  d.integration  ?? "",
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
            // The whole appliance state as JSON: a ListModel turns nested
            // objects into sub-models, and ten more flat roles for one device
            // type would be noise on every other card.
            appliance:    d.type === "appliance" ? JSON.stringify(s) : "",
            media:        (d.type === "tv" || d.type === "speaker") ? JSON.stringify(s) : "",
            issues:       d.issues ?? 0,
        }
    }

    // Order by room, then by device (channels of one strip stay together), so
    // the grid reads as rooms even though it is a single flow. A device the user
    // dragged outranks all of that and holds the place it was dropped in; the
    // ones never touched keep the default order behind them.
    function sortModel() {
        // Nothing reorders behind the user's back while they are arranging cards
        // by hand. A poll lands every four seconds with the popup open, and each
        // one used to re-sort from the *saved* order — which undid the drag in
        // progress and shuffled the grid out from under the pointer. The order on
        // screen is the intended one until the drop writes it down.
        if (root.reordering) return

        const items = []
        const manual = root.customOrder
        for (let i = 0; i < deviceModel.count; i++) {
            const it = deviceModel.get(i)
            const pos = manual.indexOf(it.modelKey)
            items.push({
                key:  it.modelKey,
                rank: pos >= 0 ? pos : Number.MAX_SAFE_INTEGER,
                // Devices with no room sink to the bottom (U+FFFF sorts last).
                // Fields are joined with NUL, which sorts before every printable
                // character, so a short field never bleeds into the next one.
                // Kept as an escape on purpose: a literal NUL byte in the source
                // makes grep treat the file as binary and stops the QML parsers.
                sort: (it.roomName || "￿").toLowerCase() + "\u0000"
                    + (it.groupName || it.deviceName).toLowerCase() + "\u0000"
                    + it.deviceName.toLowerCase(),
            })
        }
        items.sort((a, b) => a.rank !== b.rank ? a.rank - b.rank
                           : (a.sort < b.sort ? -1 : (a.sort > b.sort ? 1 : 0)))
        for (let target = 0; target < items.length; target++) {
            const cur = findIndex(items[target].key)
            if (cur >= 0 && cur !== target)
                deviceModel.move(cur, target, 1)
        }
    }

    // ── Manual order ──────────────────────────────────────────────────────────

    function fetchOrder() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", daemonUrl + "/order")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
            try {
                const keys = JSON.parse(xhr.responseText)
                if (Array.isArray(keys)) {
                    customOrder = keys
                    sortModel()
                    modelRevision++
                }
            } catch (e) {
                // A corrupt order file is not worth an error banner: the default
                // sort still works, and the next drag rewrites the file anyway.
            }
        }
        xhr.send()
    }

    // Called once, on release. Saving on every swap during a drag would mean a
    // request per card crossed, and a half-finished drag is not an intent yet.
    function saveOrder() {
        if (!orderDirty) return
        orderDirty = false

        const keys = []
        for (let i = 0; i < deviceModel.count; i++)
            keys.push(deviceModel.get(i).modelKey)
        customOrder = keys

        const xhr = new XMLHttpRequest()
        xhr.open("POST", daemonUrl + "/order")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) showError("No se pudo guardar el orden")
        }
        xhr.onerror   = () => showError("No se pudo guardar el orden: daemon sin respuesta")
        xhr.ontimeout = () => showError("No se pudo guardar el orden: sin respuesta")
        xhr.send(JSON.stringify({ keys: keys }))
    }

    function resetOrder() {
        customOrder = []
        orderDirty  = false
        sortModel()
        modelRevision++

        const xhr = new XMLHttpRequest()
        xhr.open("POST", daemonUrl + "/order")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) showError("No se pudo restablecer el orden")
        }
        xhr.send(JSON.stringify({ keys: [] }))
    }

    // A drag reports which card the pointer is over; that card decides the target
    // slot. Moving the row on the way (rather than on release) is what makes the
    // grid rearrange live under the pointer, and it costs nothing — the write to
    // the daemon happens once, on release.
    //
    // The hit test itself lives in the delegate, not here: `fullRepresentation`
    // is an implicit Component, so ids declared inside it (deviceFlow among them)
    // are out of scope for functions at this level.
    function reorderTo(key, targetKey) {
        if (targetKey === "" || targetKey === key) return

        const from = findIndex(key)
        const to   = findIndex(targetKey)
        if (from < 0 || to < 0 || from === to) return

        deviceModel.move(from, to, 1)
        orderDirty = true
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

    // TV / speaker commands beyond volume and playback. Fields that have a
    // state are patched into the card's JSON at once, like every other control;
    // keys and channel steps have none to patch.
    function tvCmd(id, action, value) {
        const field = { mute: "mute", input: "input",
                        picture_mode: "picture_mode", sound_mode: "sound_mode" }[action]
        const idx = findIndex(id)
        if (field && idx >= 0) {
            try {
                const st = JSON.parse(deviceModel.get(idx).media || "{}")
                st[field] = value
                deviceModel.setProperty(idx, "media", JSON.stringify(st))
            } catch (e) { }
        }
        postAction(id, action, value === undefined ? "{}" : JSON.stringify({value: value}), id)
    }

    function setMachine(id, state) {
        postAction(id, "machine", JSON.stringify({value: state}), id)
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

    // ── watchtv ───────────────────────────────────────────────────────────────

    function fetchStatus() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", daemonUrl + "/status")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
            try { watchtvPath = JSON.parse(xhr.responseText).watchtv || "" } catch (e) { }
        }
        xhr.send()
    }

    // The executable engine waits for the command to exit, and a source that is
    // still connected cannot be started again — so a second click on the same
    // TV would do nothing while the first window stayed open. setsid -f detaches
    // the window and returns at once.
    P5Support.DataSource {
        id: launcher
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => disconnectSource(source)
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    // The SmartThings name goes as --device: watchtv matches it to the name the
    // TV announces on the LAN, and turns the TV on through the daemon if it is
    // off. Choosing the file happens in watchtv's window — a file dialog here
    // would take focus, and the popup closes the moment it loses it.
    function launchWatchtv(deviceName) {
        if (watchtvPath === "") return
        launcher.connectSource("setsid -f " + shellQuote(watchtvPath)
                               + " --device " + shellQuote(deviceName)
                               + " >/dev/null 2>&1")
        flashMsg = "ABRIENDO WATCHTV · " + deviceName.toUpperCase()
        flashTimer.restart()
        root.expanded = false
    }

    // ── History ───────────────────────────────────────────────────────────────

    function openHistory(deviceId) {
        historyDevice = deviceId
        historyOnlyIssues = true
        activeTab = historyTab
    }

    function fetchEvents() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", daemonUrl + "/events?limit=500")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
            try {
                events = JSON.parse(xhr.responseText)
                eventsLoaded = true
            } catch (e) { /* keep the previous list */ }
        }
        xhr.send()

        const sx = new XMLHttpRequest()
        sx.open("GET", daemonUrl + "/events/summary?hours=24")
        sx.timeout = 5000
        sx.onreadystatechange = () => {
            if (sx.readyState !== XMLHttpRequest.DONE || sx.status !== 200) return
            try { eventSummary = JSON.parse(sx.responseText) } catch (e) { }
        }
        sx.send()
    }

    function clearHistory() {
        const xhr = new XMLHttpRequest()
        xhr.open("POST", daemonUrl + "/events/clear")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) showError("No se pudo borrar el historial")
            historyDevice = ""
            fetchEvents()
            fetchDevices()
        }
        xhr.send("{}")
    }

    // "14:02" today, "ayer 14:02", otherwise "12/11 14:02".
    function formatTime(ts) {
        const d = new Date(ts * 1000), now = new Date()
        const pad = n => (n < 10 ? "0" : "") + n
        const hm = pad(d.getHours()) + ":" + pad(d.getMinutes())
        const day = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        const diff = Math.round((day - new Date(d.getFullYear(), d.getMonth(), d.getDate()))
                                / 86400000)
        if (diff === 0) return hm
        if (diff === 1) return "ayer " + hm
        return pad(d.getDate()) + "/" + pad(d.getMonth() + 1) + " " + hm
    }

    function fullTime(ts) {
        const d = new Date(ts * 1000)
        const pad = n => (n < 10 ? "0" : "") + n
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
             + " " + pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds())
    }

    // Same fixed-column block as the device fact sheet, so the two paste alike.
    function eventDetail(ev) {
        const rows = [
            ["NIVEL",  ev.level.toUpperCase()],
            ["TIPO",   ev.kind],
            ["EVENTO", ev.message],
            ["CUANDO", fullTime(ev.ts)],
        ]
        if (ev.count > 1) {
            rows.push(["ÚLTIMO", fullTime(ev.last_ts)])
            rows.push(["VECES",  String(ev.count)])
        }
        if (ev.device_id) rows.push(["ID", ev.device_id])
        let out = rows.map(r => r[0].padEnd(7) + r[1]).join("\n")
        if (ev.detail) out += "\n\n" + ev.detail
        return out
    }

    // What COPIAR puts on the clipboard: the rows on screen, oldest last, one
    // line each — enough to paste into an issue or a support thread.
    function historyReport() {
        const head = "SmartThings · historial"
            + (historyDevice !== "" ? " · " + historyDeviceName : "")
            + (historyOnlyIssues ? " · solo fallos" : "")
            + " · " + fullTime(Date.now() / 1000)
        return head + "\n" + filteredEvents.map(ev =>
            fullTime(ev.last_ts) + "  " + ev.level.toUpperCase().padEnd(5) + "  "
            + (ev.device_name || "Daemon") + " — " + ev.message
            + (ev.count > 1 ? "  (×" + ev.count + " desde " + fullTime(ev.ts) + ")" : "")
            + (ev.detail ? "\n      " + ev.detail : "")
        ).join("\n")
    }

    function errorDetail(xhr) {
        try {
            const data = JSON.parse(xhr.responseText)
            if (data.error) return String(data.error).slice(0, 80)
        } catch (e) { /* not JSON */ }
        return "error " + xhr.status
    }
}
