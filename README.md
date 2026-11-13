# SmartThings KDE Widget

Control your Samsung SmartThings smart home from the KDE Plasma panel — toggle
lights, dim, run the AC, drive TVs and speakers, and read your sensors, without
opening a phone app. A small local Python daemon talks to the SmartThings cloud
and a QML plasmoid renders the controls.

![KDE Plasma 6](https://img.shields.io/badge/KDE_Plasma-6-blue)
![Python 3.11+](https://img.shields.io/badge/Python-3.11+-green)
![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue)

## Features

- Panel icon with a **badge showing how many devices are on**, and a popup
  organized into **tabs by device type**:
  **Luces · Cerraduras · Clima · Multimedia · Aparatos · Sensores · Botones ·
  Hubs** — each
  tab shows its count, empty ones stay hidden, and the bar is a single scrollable
  row rather than two wrapped ones.
- **Search** by device, room or plug name, plus a **room filter**; the grid is
  ordered by room, and each card shows the room it belongs to.
- **Rename any device locally** (✏ on hover): the new name lives only in this
  widget, never in the SmartThings cloud. See [Local device names](#local-device-names).
- **Device identity one click away** (ⓘ on hover): manufacturer, model,
  firmware, integration and the raw `deviceId`, in a panel whose text you can
  select — plus a **COPIAR** button. When something misbehaves, that is what you
  paste into a search or a support thread. See [Device identity](#device-identity).
- **Reorder the grid by hand** (⇅ in the header): cards rearrange live under the
  pointer and the order is saved by the daemon, so it survives restarts and
  plasmashell reloads. See [Manual order](#manual-order).
- **History for diagnosis** (Historial tab): the daemon records state changes,
  every command and its outcome, and every failed cloud read, with failures
  highlighted. A repeat of the same failure folds into one row (`×37 · desde
  14:44`), a chip row ranks the devices with the most problems in the last 24 h,
  and a card with recent issues shows a `!N` badge that jumps straight to its
  history. See [History](#history).
- Devices are classified by SmartThings **component categories** (the same
  signal the official app uses), so a TV or AC — which also expose a `switch` —
  never gets misfiled as a light.
- **Lights / switches / plugs**: 4:3 tiles, one tap to toggle; multi-outlet
  plugs expand into individual tiles. The shorter tile fits three rows of devices
  where a square one fit two.
- **Buttons**: the same tiles (read-only) rather than full-width rows, so the
  grid keeps one shape. A low battery takes over the tile's second line, which
  is the one thing the row layout showed and a tile otherwise would not.
- **Locks**: closing is one tap, **opening asks for confirmation** first.
- **Dimmers**: brightness slider (`switchLevel`).
- **Air conditioners**: on/off, target temperature (−/+ within the device's
  range), mode (auto/cool/dry/fan/heat), plus current temperature & humidity.
- **TVs**: on/off, volume slider, play/pause/stop, current input.
- **Speakers**: play/pause/stop, volume, and what's currently playing.
- **Appliances** (washer/dryer…): on/off and machine state.
- **Sensors**: read-only temperature, humidity, motion/contact, battery — with a
  desktop notification (`notify-send`) when a motion sensor becomes active.
- **The wheel always scrolls the list**: a brightness or volume slider under the
  pointer hands the turn back to the list instead of swallowing it, so scrolling
  past a volume bar never moves it by accident.
- **Surface instead of outline**: cards have no resting border — a grid of
  outlined rectangles reads as a grille. The line comes back on hover and on
  keyboard focus. Tiles join the tab chain, so you can Tab to a device and toggle
  it with Space or Enter.
- **Names in the desktop sans, everything else monospaced**: uppercase + mono +
  8 px flattens a name into another field, so device names use the Plasma UI font
  in sentence case and the terminal type is kept for labels, units and readouts.
- **One colour per function**: teal is structure (borders, tabs, chrome), cream is
  the device name, warm grey is secondary data, coral means *on*. A device that
  is on gets a warm wash plus a coral bar rather than a flood of coral — and one
  the hub can't reach is drawn with a diagonal hatch, so "off" and "unreachable"
  never look alike. Every text pair clears WCAG AA (the old dark-on-coral name
  was 4.16:1; the cream name is 11.8:1).
- **Optimistic UI**: taps apply instantly; the daemon patches its cache first and
  reconciles with the cloud a few seconds later, so controls never "bounce". A
  command that fails says so in the popup instead of silently reverting.
- **Adaptive polling**: the widget re-reads the daemon every 4 s while the popup
  is open and every 30 s when closed; the daemon itself sweeps the cloud every
  20 s. The refresh button (and middle-click on the panel icon) forces a real
  sweep via `POST /refresh` and spins until it lands — roughly 5 s for 33
  devices, because the per-device calls run in a thread pool instead of one after
  another. The footer shows how old the *cloud* read is, not when the widget last
  re-read the cache.
- Sizes and type follow the **Plasma font settings**, so the widget stays legible
  on HiDPI screens; the tile grid reflows to the widget's width.
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
│  │  GET /devices: 4s open/30s   │   │
│  │  POST /devices/{id}/<action> │   │
│  └──────────────┬───────────────┘   │
└─────────────────┼───────────────────┘
                  │ HTTP 127.0.0.1:7182
┌─────────────────┼───────────────────┐
│ smartthings-daemon (Python, stdlib) │
│  ┌──────────────┴───────────────┐   │
│  │  smartthings_service.py      │   │
│  │  sweeps the cloud every 20 s │   │
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
| GET  | `/devices` | List all devices with state, room and local name |
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
| POST | `/refresh` | Force a cloud sweep now; returns when it lands |
| GET  | `/events` | History, newest first (`?device=&level=warn&since=&limit=`) |
| GET  | `/events/summary` | Warnings/errors per device (`?hours=24`) |
| POST | `/events/clear` | Wipe the history |
| GET  | `/aliases` | Local names, keyed by device id / `{id}_{outlet}` |
| POST | `/alias` | Local rename `{"key","name"}` — empty name restores the original |
| POST | `/channel_name` | Legacy channel rename `{"device_id","outlet","name"}` |
| GET  | `/order` | Manual card order, as a list of keys (`[]` = default sort) |
| POST | `/order` | Save it: `{"keys": [...]}` — an empty list restores the default |

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

### Local device names

Every device (and every channel of a multi-switch) can be renamed from the
widget: hover the card and click the pencil. The new name lives only in
`~/.config/smartthings-widget/aliases.json` — nothing is renamed in the
SmartThings cloud, so the app on your phone keeps the original name. Clearing
the field (or the undo button) restores it. The older
`channel_names.json` is imported automatically on first run.

### Device identity

The ⓘ button on any card opens a panel with everything you need to identify the
physical device: **manufacturer, model, firmware, integration and `deviceId`**.
The text is selectable, and **COPIAR** puts the whole block on the clipboard.

Where those values come from depends on how the device reaches SmartThings, and
the daemon reads all three shapes in this order:

| Source | Devices | Fields |
|---|---|---|
| `ocf` | Samsung's own gear | maker, `modelNumber`, `firmwareVersion` |
| `viper` | cloud-to-cloud integrations | maker, `modelName`, `swVersion` |
| `deviceManufacturerCode` | Zigbee / Z-Wave | the real maker |

`manufacturerName` is used only as a last resort: for Zigbee and Z-Wave devices
it is usually whoever published the driver, not who built the device. Fields
that no integration reports are left out of the panel rather than shown empty —
firmware, for instance, is typically only there on Samsung devices, and LAN
devices often report no model at all. The integration line is the device `type`
SmartThings reports (`OCF`, `VIPER`, `LAN`, `ZIGBEE`, `HUB`…), which is the
first thing worth knowing when a device stops answering: it tells you whether to
look at your hub, your LAN or someone else's cloud.

### Manual order

⇅ in the header enters reorder mode: a banner appears, every card gets an
outline, and dragging one moves it. Cards rearrange live under the pointer;
**LISTO** leaves the mode and **RESTABLECER** goes back to the default ordering
by room.

It is a mode rather than a press-and-hold because these cards are covered in
sliders, switches and playback buttons — any long-press gesture would fight
them. While the mode is on, a veil covers each card whole, so a drag that starts
on a volume bar moves the card instead of the volume.

The order lives in `~/.config/smartthings-widget/order.json` (a list of the same
keys as the aliases), not in the plasmoid config: keeping it next to the daemon
means it survives plasmashell reloads and reinstalls, and any future client can
read the same arrangement. Devices missing from the list — a newly paired one,
say — sort after the ordered ones by room.

### History

The daemon keeps an event log in `~/.local/state/smartthings-widget/events.jsonl`
(state, not config: deleting it costs nothing but history). What goes in:

| Kind | Examples | Level |
|---|---|---|
| `state` | on/off, mode, setpoint, TV input, washer cycle, lock, motion | info |
| `connectivity` | a device going offline / coming back | warn / info |
| `command` | every command sent from the widget, and whether it worked | info / error |
| `command` | **accepted but no effect**: SmartThings said ACCEPTED, yet 6 s later the device still is not in the requested state | warn |
| `cloud` | a per-device `/status` or `/health` read that failed (`HTTP 500 UnexpectedError`) | error |
| `daemon` | start, a whole sweep failing (DNS, token) | info / error |

Readings that drift on their own — temperature, humidity, volume, brightness —
are left out; they would bury the events that matter.

The same failure within an hour is **folded** into one event with a count and a
first/last time, instead of one row every 20 s sweep. Request ids are stripped
for that comparison (they differ on every call) but kept in the detail panel —
click a row to see it, with the raw cloud error, and COPIAR to paste it.

The "accepted but no effect" warning exists because SmartThings answers
ACCEPTED to commands a device then ignores — a washer with Smart Control off,
a TV in standby. Without it, that failure is indistinguishable from success.

A failed `/status` read now **keeps the last known state** (and marks the device
`stale`) instead of emptying it; before, a TV that was on rendered as off until
the next sweep happened to succeed.

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

[GNU General Public License v3.0](LICENSE)
