import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root

    readonly property string daemonUrl: "http://127.0.0.1:7182"

    property bool   daemonOk:   false
    property bool   configured: false
    property string location:   ""
    property bool   pending:    false
    property string message:    ""
    property bool   isError:    false

    Component.onCompleted: fetchStatus()

    // Poll while waiting for the browser callback
    Timer {
        interval: 2000
        repeat:   true
        running:  root.pending
        onTriggered: fetchStatus()
    }

    function fetchStatus() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", daemonUrl + "/auth/status")
        xhr.timeout = 3000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                const s   = JSON.parse(xhr.responseText)
                daemonOk  = true
                configured = s.configured
                location  = s.location || ""
                // Transition: was pending, now done
                if (root.pending && !s.pending) {
                    if (s.error) {
                        message = "Error: " + s.error
                        isError = true
                    } else {
                        message = "✓ Autorización completada correctamente"
                        isError = false
                    }
                }
                pending = s.pending
            } else {
                daemonOk = false
            }
        }
        xhr.onerror = xhr.ontimeout = () => { daemonOk = false }
        xhr.send()
    }

    function startAuth() {
        message = ""
        isError = false
        const xhr = new XMLHttpRequest()
        xhr.open("POST", daemonUrl + "/auth/start")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 5000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                const r = JSON.parse(xhr.responseText)
                if (r.ok && r.url) {
                    pending = true
                    Qt.openUrlExternally(r.url)
                    message = "Esperando autorización en el navegador…"
                    isError = false
                } else {
                    message = "Error: " + (r.error || "desconocido")
                    isError = true
                }
            } else {
                message = "No se pudo contactar el daemon"
                isError = true
            }
        }
        xhr.onerror = xhr.ontimeout = () => {
            message = "Daemon no responde"
            isError = true
        }
        xhr.send("{}")
    }

    // ── Estado actual ────────────────────────────────────────────────────
    QQC2.Label {
        Kirigami.FormData.label: "Daemon:"
        text:  daemonOk ? "Corriendo ✓" : "Offline ✗"
        color: daemonOk ? Kirigami.Theme.positiveTextColor
                        : Kirigami.Theme.negativeTextColor
    }

    QQC2.Label {
        Kirigami.FormData.label: "Ubicación:"
        text: location || "—"
    }

    QQC2.Label {
        Kirigami.FormData.label: "Tokens:"
        text:  configured ? "Configurados ✓" : "No configurados"
        color: configured ? Kirigami.Theme.positiveTextColor
                          : Kirigami.Theme.neutralTextColor
    }

    // ── Re-autorización ──────────────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: "Re-autorizar"
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        text: "Abre el navegador para re-vincular tu cuenta SmartThings.\n" +
              "Necesario si los tokens expiraron o la sesión fue revocada."
        wrapMode: Text.WordWrap
        opacity: 0.75
    }

    QQC2.Button {
        Kirigami.FormData.label: " "
        text:    pending ? "Esperando respuesta del navegador…" : "Abrir autorización en navegador"
        enabled: daemonOk && !pending
        icon.name: "internet-web-browser"
        onClicked: startAuth()
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        visible: message !== ""
        text:    message
        color:   isError ? Kirigami.Theme.negativeTextColor
                         : (message.startsWith("Esperando")
                            ? Kirigami.Theme.textColor
                            : Kirigami.Theme.positiveTextColor)
        wrapMode: Text.WordWrap
    }

    // ── Nota primer uso ──────────────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: "Configuración inicial"
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        text: "Para la configuración inicial (primera vez) ejecuta\n" +
              "python3 setup.py  desde el directorio daemon/ del repositorio."
        opacity: 0.6
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
    }
}
