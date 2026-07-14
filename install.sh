#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_DIR="$SCRIPT_DIR/daemon"
PLASMOID_DIR="$SCRIPT_DIR/plasmoid/smartthings-control"
SERVICE_DIR="$HOME/.config/systemd/user"
PLASMOID_DEST="$HOME/.local/share/plasma/plasmoids/org.kde.smartthings-control"

echo "=== SmartThings KDE Widget Installer ==="
echo ""

# ── 1. Python ≥ 3.11 ──────────────────────────────────────────────────────────
echo "[1/5] Checking Python version…"
PY=$(python3 -c 'import sys; print(sys.version_info >= (3, 11))' 2>/dev/null || echo False)
if [[ "$PY" != "True" ]]; then
    echo "Error: Python 3.11+ is required."
    exit 1
fi
echo "  OK: $(python3 --version)"

# ── 2. SmartThings credentials ────────────────────────────────────────────────
echo ""
echo "[2/5] SmartThings auth setup (cli_bridge)…"
echo "  Requires the SmartThings CLI logged in first:"
echo "    npm install -g @smartthings/cli && smartthings login"
if [[ -f "$HOME/.config/smartthings-widget/config.json" ]]; then
    echo "  Config already exists at ~/.config/smartthings-widget/config.json"
    read -rp "  Re-run setup? [y/N] " ans
    if [[ "${ans,,}" == "y" ]]; then
        python3 "$DAEMON_DIR/setup.py"
    fi
else
    python3 "$DAEMON_DIR/setup.py"
fi

# ── 3. systemd user service ───────────────────────────────────────────────────
echo ""
echo "[3/5] Installing systemd user service…"
mkdir -p "$SERVICE_DIR"
cat > "$SERVICE_DIR/smartthings-daemon.service" << EOF
[Unit]
Description=SmartThings Control Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${DAEMON_DIR}
ExecStart=$(command -v python3) -u smartthings_service.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable smartthings-daemon.service
systemctl --user start smartthings-daemon.service
loginctl enable-linger "$USER" 2>/dev/null || true
echo "  Service enabled and started."

# ── 4. Plasma plasmoid ───────────────────────────────────────────────────────
echo ""
echo "[4/5] Installing Plasma plasmoid…"
mkdir -p "$(dirname "$PLASMOID_DEST")"
rm -rf "$PLASMOID_DEST"
ln -s "$PLASMOID_DIR" "$PLASMOID_DEST"
rm -rf "$HOME/.cache/plasmashell/qmlcache/" 2>/dev/null || true
echo "  Plasmoid installed (symlink → $PLASMOID_DIR)."

# ── 5. Add widget to panel ───────────────────────────────────────────────────
echo ""
echo "[5/5] Adding widget to KDE panel…"
DBUS=unix:path=/run/user/$(id -u)/bus
if command -v qdbus6 &>/dev/null && \
   DBUS_SESSION_BUS_ADDRESS=$DBUS qdbus6 org.kde.plasmashell /PlasmaShell \
     org.kde.PlasmaShell.evaluateScript 'print(panels().length)' &>/dev/null; then

    DBUS_SESSION_BUS_ADDRESS=$DBUS \
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
var ps = panels();
for (var i = 0; i < ps.length; i++) {
    var ws = ps[i].widgets();
    var found = false;
    for (var j = 0; j < ws.length; j++) {
        if (ws[j].type === "org.kde.smartthings-control") { found = true; break; }
    }
    if (!found) {
        ps[i].addWidget("org.kde.smartthings-control");
        print("added to panel " + ps[i].id);
        break;
    }
}
' 2>/dev/null && echo "  Widget added to panel." \
             || echo "  Add the widget manually: right-click panel → Add widgets → SmartThings Control"
else
    echo "  Plasma not running — add the widget manually after login."
fi

echo ""
echo "Done! Click the SmartThings icon in your panel to control your devices."
echo ""
echo "Useful commands:"
echo "  systemctl --user status smartthings-daemon"
echo "  journalctl --user -u smartthings-daemon -f"
echo "  curl http://127.0.0.1:7182/devices | python3 -m json.tool"
