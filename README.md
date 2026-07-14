# SmartThings KDE Widget

Control your Samsung SmartThings smart home from the KDE Plasma panel — toggle
lights, dim, run the AC, drive TVs and speakers, and read your sensors, without
opening a phone app. A small local Python daemon talks to the SmartThings cloud
and a QML plasmoid renders the controls.

![KDE Plasma 6](https://img.shields.io/badge/KDE_Plasma-6-blue)
![Python 3.11+](https://img.shields.io/badge/Python-3.11+-green)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

## Features

- Panel icon with a popup, organized into **tabs by device type**:
  **Luces · Clima · Multimedia · Aparatos · Sensores · Botones · Hubs**
- Devices are classified by SmartThings **component categories** (the same
  signal the official app uses), so a TV or AC — which also expose a `switch` —
  never gets misfiled as a light.
- **Lights / switches / plugs**: square tiles, one tap to toggle; multi-outlet
  plugs expand into individual tiles you can rename inline (✏).
- **Dimmers**: brightness slider (`switchLevel`).
- **Air conditioners**: on/off, target temperature (−/+ within the device's
  range), mode (auto/cool/dry/fan/heat), plus current temperature & humidity.
- **TVs**: on/off, volume slider, play/pause/stop, current input.
- **Speakers**: play/pause/stop, volume, and what's currently playing.
- **Appliances** (washer/dryer…): on/off and machine state.
- **Sensors**: read-only temperature, humidity, motion/contact, battery — with a
  desktop notification (`notify-send`) when a motion sensor becomes active.
- **Optimistic UI**: taps apply instantly; the daemon patches its cache first and
  reconciles with the cloud a few seconds later, so controls never "bounce".
- Runs as a **systemd user service** (starts at boot). The access token is
  refreshed automatically and never expires in practice.
- Optional PyQt6 **system tray** (`systray/systray.py`) as an alternative to the
  plasmoid.

## How devices are mapped

SmartThings tags every device component with **categories**. The daemon maps
those (with priority over raw capabilities) to a widget type:

| Widget type | SmartThings category / capability | Controls |
|---|---|---|
| Light / Switch / Plug | `Light`, `Switch`, `SmartPlug` (+ `switch`) | on/off |
| Dimmer | `switchLevel` | brightness |
| AC / Climate | `AirConditioner`, `Thermostat` | on/off, setpoint, mode |
| TV | `Television`, `SmartMonitor` | on/off, volume, play/pause |
| Speaker | `Speaker`, `NetworkAudio` | play/pause, volume |
| Appliance | `Washer`, `Dryer`, `Dishwasher`… | on/off, state |
| Lock | `lock` | lock / unlock |
| Sensor | `MotionSensor`, `MultiFunctionalSensor`, `ContactSensor`… | read-only |
| Button | `RemoteController` (+ `button`) | read-only |
| Hub | `Hub` / device type `HUB` | read-only |

## Authentication — how it works (and why)

SmartThings makes long-lived personal auth awkward: **Personal Access Tokens
created after Dec 2024 expire in 24 h**, and the OAuth-In "SmartApp" consent
screen is currently unreliable (server-side `An unexpected error occurred`).

So this widget uses a **CLI bridge** (`auth_mode: cli_bridge`): it borrows the
login from the official **SmartThings CLI**. The CLI signs you in with a public
PKCE OAuth client that issues a **refreshable** token (scope `controller:stCli`,
which can read *and* control devices). `setup.py` copies that token into the
widget config, and the daemon then refreshes it itself — indefinitely — against
`auth-global.api.smartthings.com` using the CLI's public client id. No browser
consent, no 24 h expiry, no secret to guard.

> A full OAuth-In flow is still included (`setup_oauth.py`) as a fallback for if
> SmartThings fixes their consent screen.

## Requirements

- KDE Plasma 6
- Python 3.11+ (standard library only — no pip packages)
- Node.js + npm (only to install the SmartThings CLI, one-time)
- A SmartThings account with devices

## Installation

### 1. Clone

```bash
git clone https://github.com/Gu7i/kde-smartthings-widget.git
cd kde-smartthings-widget
```

### 2. Log in with the SmartThings CLI (one-time)

```bash
npm install -g @smartthings/cli
smartthings login          # opens your browser, sign in to your account
```

### 3. Run the installer

```bash
chmod +x install.sh
./install.sh
```

The installer will:

- run `daemon/setup.py`, which copies the CLI token into
  `~/.config/smartthings-widget/config.json` and lists your devices,
- install and enable the `smartthings-daemon` systemd user service,
- install the plasmoid (symlinked from the repo) and add it to your panel.

### Manual setup (alternative)

```bash
# 1. Bootstrap auth from the CLI login
cd daemon && python3 setup.py

# 2. Start the daemon
systemctl --user enable --now smartthings-daemon.service

# 3. Install the plasmoid
ln -s "$PWD/../plasmoid/smartthings-control" \
      ~/.local/share/plasma/plasmoids/org.kde.smartthings-control

# 4. Add it: right-click panel → Add widgets → "SmartThings Control"
```

### Uninstall

```bash
./uninstall.sh
```

## Architecture

```
┌─────────────────────────────────────┐
│  KDE Panel                          │
│  ┌──────────────────────────────┐   │
│  │  Plasmoid (QML)              │   │
│  │  polls GET /devices every 8s │   │
│  │  POST /devices/{id}/<action> │   │
│  └──────────────┬───────────────┘   │
└─────────────────┼───────────────────┘
                  │ HTTP 127.0.0.1:7182
┌─────────────────┼───────────────────┐
│ smartthings-daemon (Python, stdlib) │
│  ┌──────────────┴───────────────┐   │
│  │  smartthings_service.py      │   │
│  │  polls the cloud every 20 s, │   │
│  │  caches state, optimistic     │   │
│  │  patch + reconcile on command │   │
│  └──────────────┬───────────────┘   │
└─────────────────┼───────────────────┘
                  │ HTTPS (SmartThings API v1)
           SmartThings Cloud
```

> SmartThings has no simple client WebSocket, so state is kept fresh by polling.
> Optimistic UI keeps taps feeling instant.

## Daemon API (`http://127.0.0.1:7182`)

| Method | Path | Description |
|---|---|---|
| GET  | `/devices` | List all devices with state |
| GET  | `/devices/{id}` | One device |
| GET  | `/status` | Daemon health + device count |
| GET  | `/auth/status` | Auth state |
| POST | `/devices/{id}/on` · `/off` · `/toggle` | Switch (body `{"outlet": 0}` for multi) |
| POST | `/devices/{id}/brightness` | `{"value": 75}` |
| POST | `/devices/{id}/volume` | `{"value": 30}` (TV / speaker) |
| POST | `/devices/{id}/play` · `/pause` · `/stop` | Media playback |
| POST | `/devices/{id}/mode` | `{"value": "cool"}` (AC) |
| POST | `/devices/{id}/setpoint` | `{"value": 22}` (AC) |
| POST | `/devices/{id}/lock` · `/unlock` | Door lock |
| POST | `/channel_name` | Rename a channel `{"device_id","outlet","name"}` |

## Configuration

`~/.config/smartthings-widget/config.json` (mode 600), written by `setup.py`:

```json
{
  "auth_mode": "cli_bridge",
  "cli_client_id": "…",
  "refresh_url": "https://auth-global.api.smartthings.com/oauth/token",
  "access_token": "…",
  "refresh_token": "…",
  "token_expires": "…"
}
```

Channel aliases live in `~/.config/smartthings-widget/channel_names.json`.

## Useful commands

```bash
systemctl --user status smartthings-daemon
systemctl --user restart smartthings-daemon
journalctl --user -u smartthings-daemon -f

curl http://127.0.0.1:7182/devices | python3 -m json.tool

# Re-bootstrap auth (e.g. after a very long downtime)
cd daemon && python3 setup.py
```

## Troubleshooting

- **`setup.py` says it can't find CLI credentials** — run `smartthings login`
  first; it must succeed in a browser.
- **Daemon shows 401 / no devices** — the borrowed refresh token expired (only
  happens after ~29 days of the daemon never running). Just `smartthings login`
  again and re-run `python3 setup.py`.
- **Widget shows "DAEMON OFFLINE"** — check `systemctl --user status
  smartthings-daemon` and the journal.
- **Tabs/UI didn't update after an edit** — Plasma caches QML:
  `systemctl --user restart plasma-plasmashell`.

## System tray (alternative to the plasmoid)

```bash
sudo pacman -S python-pyqt6   # or your distro's PyQt6 package
python3 systray/systray.py
```

## License

[MIT](LICENSE)
