#!/usr/bin/env bash
set -euo pipefail

echo "=== SmartThings KDE Widget Uninstaller ==="
echo ""

# ── 1. Stop and disable systemd service ──────────────────────────────────────
echo "[1/4] Removing systemd service…"
systemctl --user stop    smartthings-daemon.service 2>/dev/null || true
systemctl --user disable smartthings-daemon.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/smartthings-daemon.service"
rm -f "$HOME/.config/systemd/user/default.target.wants/smartthings-daemon.service"
systemctl --user daemon-reload
echo "  Service removed."

# ── 2. Remove widget from KDE panel ──────────────────────────────────────────
echo ""
echo "[2/4] Removing widget from panel…"
DBUS=unix:path=/run/user/$(id -u)/bus
if command -v qdbus6 &>/dev/null && \
   DBUS_SESSION_BUS_ADDRESS=$DBUS qdbus6 org.kde.plasmashell /PlasmaShell \
     org.kde.PlasmaShell.evaluateScript 'print("ok")' &>/dev/null; then

    DBUS_SESSION_BUS_ADDRESS=$DBUS \
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
var removed = 0;
var ps = panels();
for (var i = 0; i < ps.length; i++) {
    var ws = ps[i].widgets();
    for (var j = ws.length - 1; j >= 0; j--) {
        if (ws[j].type === "org.kde.smartthings-control") {
            ws[j].remove();
            removed++;
        }
    }
}
print("removed " + removed + " widget(s)");
' 2>/dev/null && echo "  Widget removed from panel." || true
else
    echo "  Plasma not running — widget will be gone after next login."
fi

# ── 3. Remove plasmoid files ──────────────────────────────────────────────────
echo ""
echo "[3/4] Removing plasmoid files…"
rm -rf "$HOME/.local/share/plasma/plasmoids/org.kde.smartthings-control"
rm -rf "$HOME/.cache/plasmashell/qmlcache/" 2>/dev/null || true
echo "  Plasmoid removed."

# ── 4. Optionally remove credentials ─────────────────────────────────────────
echo ""
echo "[4/4] Credentials at ~/.config/smartthings-widget/config.json"
if [[ -f "$HOME/.config/smartthings-widget/config.json" ]]; then
    read -rp "  Delete credentials and tokens? [y/N] " ans
    if [[ "${ans,,}" == "y" ]]; then
        rm -rf "$HOME/.config/smartthings-widget/"
        echo "  Credentials removed."
    else
        echo "  Kept."
    fi
else
    echo "  Not found, skipping."
fi

echo ""
echo "Done. The SmartThings widget has been uninstalled."
