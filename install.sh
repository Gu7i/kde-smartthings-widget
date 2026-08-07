#!/usr/bin/env bash
set -euo pipefail

# plasmashell is not necessarily managed by systemd. When the unit is disabled
# and the session launches plasmashell directly (the default here), a
# `systemctl --user restart plasma-plasmashell` starts a *second* instance that
# exits at once on the single-instance guard: the running shell never reloads,
# so new QML is never picked up. Verified 2026-08-07 — the unit was
# inactive/disabled while plasmashell was running normally.
restart_plasmashell() {
    if systemctl --user is-active --quiet plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service
    elif pgrep -x plasmashell >/dev/null 2>&1; then
        # --replace takes the DBus name over from the running instance, which
        # is the only thing that actually reloads the QML here.
        setsid plasmashell --replace >/dev/null 2>&1 &
        sleep 3
    else
        echo "  plasmashell isn't running — it will pick this up at login."
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_DIR="$SCRIPT_DIR/daemon"
PLASMOID_DIR="$SCRIPT_DIR/plasmoid/smartthings-control"
SERVICE_DIR="$HOME/.config/systemd/user"
PLASMOID_DEST="$HOME/.local/share/plasma/plasmoids/org.kde.smartthings-control"

MODE="${1:-install}"

case "$MODE" in
    install|link) ;;
    *)
        echo "Usage: $0 [install|link]"
        echo "  install  Full install: daemon, service and plasmoid (default)"
        echo "  link     Only (re)link the plasmoid, for development"
        exit 1
        ;;
esac

# Shared by `link` and by the plasmoid step of a full install, so the two
# report the same thing. -e is false for a dangling symlink, so test -L as
# well or a broken link would survive and ln would fail on it.
link_plasmoid() {
    if [[ "$(readlink -f "$PLASMOID_DEST" 2>/dev/null)" == "$PLASMOID_DIR" ]]; then
        echo "Already linked to this checkout."
    else
        if [[ -e "$PLASMOID_DEST" || -L "$PLASMOID_DEST" ]]; then
            echo "Replacing $PLASMOID_DEST..."
            rm -rf "$PLASMOID_DEST"
        fi
        mkdir -p "$(dirname "$PLASMOID_DEST")"
        ln -s "$PLASMOID_DIR" "$PLASMOID_DEST"
        echo "Linked $PLASMOID_DEST -> $PLASMOID_DIR"
    fi
    rm -rf "$HOME/.cache/plasmashell/qmlcache/" 2>/dev/null || true
}

# The daemon, the service and the panel step are all irrelevant when the only
# thing you want is to point the plasmoid at a checkout again.
if [[ "$MODE" == "link" ]]; then
    link_plasmoid
    restart_plasmashell
    exit 0
fi


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
link_plasmoid

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
