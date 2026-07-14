#!/usr/bin/env python3
"""
SmartThings system tray — quick device toggle from the KDE panel.
Requires: python-pyqt6  (sudo pacman -S python-pyqt6)
"""

import json
import sys
import threading
import urllib.request
import urllib.error
from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PyQt6.QtGui import QIcon, QAction
from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QObject

DAEMON_URL = "http://127.0.0.1:7182"
POLL_MS = 8000


def daemon_get(path: str) -> list | dict | None:
    try:
        with urllib.request.urlopen(DAEMON_URL + path, timeout=4) as r:
            return json.loads(r.read())
    except Exception:
        return None


def daemon_post(path: str, body: dict = None) -> bool:
    data = json.dumps(body or {}).encode()
    req = urllib.request.Request(
        DAEMON_URL + path, data=data,
        headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=4) as r:
            return json.loads(r.read()).get("ok", False)
    except Exception:
        return False


class Worker(QObject):
    devices_updated = pyqtSignal(list)

    def fetch(self):
        devices = daemon_get("/devices")
        if isinstance(devices, list):
            self.devices_updated.emit(devices)


class SmartThingsTray(QSystemTrayIcon):
    def __init__(self, app: QApplication):
        super().__init__()
        self._app = app
        self._devices: list = []
        self._worker = Worker()
        self._worker.devices_updated.connect(self._on_devices)

        self.setIcon(QIcon.fromTheme("smartphone", QIcon.fromTheme("applications-utilities")))
        self.setToolTip("SmartThings Control")

        self._menu = QMenu()
        self._header = self._menu.addAction("SmartThings — cargando…")
        self._header.setEnabled(False)
        self._menu.addSeparator()
        self._device_actions: list[QAction] = []
        self._menu.addSeparator()
        quit_action = self._menu.addAction("Salir")
        quit_action.triggered.connect(app.quit)
        self.setContextMenu(self._menu)

        self._timer = QTimer()
        self._timer.setInterval(POLL_MS)
        self._timer.timeout.connect(self._poll)
        self._timer.start()
        self._poll()

        self.activated.connect(self._on_activated)
        self.show()

    def _poll(self):
        threading.Thread(target=self._worker.fetch, daemon=True).start()

    def _on_devices(self, devices: list):
        self._devices = devices
        online = sum(1 for d in devices if d.get("online"))
        self._header.setText(f"SmartThings — {online}/{len(devices)} online")

        # Remove old device actions
        for a in self._device_actions:
            self._menu.removeAction(a)
        self._device_actions.clear()

        # Rebuild (insert before the last separator+quit)
        actions = self._menu.actions()
        insert_before = actions[-2] if len(actions) >= 2 else None

        for dev in sorted(devices, key=lambda d: d["name"]):
            dtype = dev.get("type", "switch")
            state = dev.get("state", {})
            name = dev["name"]
            online = dev.get("online", False)

            if dtype == "sensor":
                temp = state.get("temperature", "")
                hum  = state.get("humidity", "")
                label = f"  🌡 {name}: {temp}  {hum}".strip()
                action = QAction(label)
                action.setEnabled(False)
            elif dtype == "lock":
                locked = state.get("locked")
                icon = "🔒" if locked else "🔓"
                label = f"  {icon} {name}"
                action = QAction(label)
                if not online:
                    action.setEnabled(False)
                else:
                    did = dev["id"]
                    act = "lock" if not locked else "unlock"
                    action.triggered.connect(lambda _, d=did, a=act: daemon_post(f"/devices/{d}/{a}"))
            elif dtype == "multi_switch":
                channels = state.get("channels", [])
                on_count = sum(channels)
                label = f"  🔌 {name} ({on_count}/{len(channels)} on)"
                action = QAction(label)
                if not online:
                    action.setEnabled(False)
                else:
                    did = dev["id"]
                    action.triggered.connect(lambda _, d=did: daemon_post(f"/devices/{d}/toggle"))
            else:
                is_on = state.get("on", False)
                icon = "●" if is_on else "○"
                label = f"  {icon} {name}"
                action = QAction(label)
                action.setCheckable(True)
                action.setChecked(is_on)
                if not online:
                    action.setEnabled(False)
                else:
                    did = dev["id"]
                    action.triggered.connect(lambda _, d=did: self._toggle(d))

            if insert_before:
                self._menu.insertAction(insert_before, action)
            else:
                self._menu.addAction(action)
            self._device_actions.append(action)

    def _toggle(self, device_id: str):
        threading.Thread(
            target=lambda: daemon_post(f"/devices/{device_id}/toggle"),
            daemon=True
        ).start()
        QTimer.singleShot(400, self._poll)

    def _on_activated(self, reason):
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self._menu.popup(self.geometry().topLeft())


def main():
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    if not QSystemTrayIcon.isSystemTrayAvailable():
        print("No system tray available", file=sys.stderr)
        sys.exit(1)

    tray = SmartThingsTray(app)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
