#!/usr/bin/env python3
"""
SmartThings local HTTP daemon — exposes device state and control on localhost:7182.

Endpoints:
  GET  /devices            → list all devices
  GET  /devices/{id}       → single device info
  POST /devices/{id}/on    → turn on (body: {"outlet": 0} optional)
  POST /devices/{id}/off   → turn off
  POST /devices/{id}/toggle
  POST /devices/{id}/brightness  (body: {"value": 75})
  POST /devices/{id}/lock | /unlock
  POST /refresh            → force a cloud sweep now (returns when it lands)
  POST /alias              → rename any device/channel locally (body: {"key", "name"})
  GET  /aliases
  POST /channel_name       → rename a multi-switch channel (legacy shim over /alias)
  GET  /channel_names
  GET  /auth/status        → auth state
  POST /auth/start         → begin OAuth flow (returns authorization URL)
  GET  /callback           → OAuth redirect target
  GET  /status             → daemon health
"""

import json
import os
import secrets
import subprocess
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CONFIG_FILE        = Path.home() / ".config" / "smartthings-widget" / "config.json"
CHANNEL_NAMES_FILE = Path.home() / ".config" / "smartthings-widget" / "channel_names.json"
ALIASES_FILE       = Path.home() / ".config" / "smartthings-widget" / "aliases.json"
PORT = 7182
POLL_INTERVAL = 20  # seconds between cloud polls (no WebSocket available)


# ── Local names ───────────────────────────────────────────────────────────────
# Aliases are purely local: nothing is ever renamed in the SmartThings cloud.
# Keyed by device id, or "{device_id}_{outlet}" for a multi-switch channel.

def _load_channel_names() -> dict:
    try:
        if CHANNEL_NAMES_FILE.exists():
            with open(CHANNEL_NAMES_FILE) as f:
                return json.load(f)
    except Exception as e:
        print(f"[channel-names] {e}", file=sys.stderr)
    return {}


def _load_aliases() -> dict:
    try:
        if ALIASES_FILE.exists():
            with open(ALIASES_FILE) as f:
                return json.load(f)
    except Exception as e:
        print(f"[aliases] {e}", file=sys.stderr)
        return {}
    return _migrate_channel_names()


def _migrate_channel_names() -> dict:
    """One-time import of the older per-channel name file into the alias map."""
    aliases = {}
    for did, names in _load_channel_names().items():
        for i, name in enumerate(names or []):
            if name:
                aliases[f"{did}_{i}"] = name
    if aliases:
        _save_aliases(aliases)
    return aliases


def _save_aliases(data: dict) -> None:
    ALIASES_FILE.parent.mkdir(parents=True, exist_ok=True)
    ALIASES_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2))


def _set_alias(key: str, name: str) -> None:
    """Store a local name for `key`; an empty name restores the original."""
    data = _load_aliases()
    if name:
        data[key] = name
    else:
        data.pop(key, None)
    _save_aliases(data)


def _with_aliases(dev: dict, aliases: dict) -> dict:
    """Copy of `dev` with local names applied; the cloud name stays in orig_name."""
    did      = dev["id"]
    state    = dev.get("state") or {}
    channels = state.get("channels")
    alias    = aliases.get(did)
    ch_keys  = [f"{did}_{i}" for i in range(len(channels))] if channels else []

    if not alias and not any(k in aliases for k in ch_keys):
        return dev

    dev = dict(dev)
    if alias:
        dev["orig_name"] = dev["name"]
        dev["name"]      = alias
    if ch_keys:
        dev["state"] = state = dict(state)
        state["channel_names"] = [aliases.get(k, "") for k in ch_keys]
    return dev


def load_config() -> dict:
    if not CONFIG_FILE.exists():
        print(f"Config not found: {CONFIG_FILE}", file=sys.stderr)
        print("Run: python3 setup.py  to configure credentials", file=sys.stderr)
        sys.exit(1)
    with open(CONFIG_FILE) as f:
        return json.load(f)


def save_tokens(access_token: str, refresh_token: str) -> None:
    """Persist rotated tokens back to config (SmartThings rotates refresh tokens)."""
    try:
        cfg = load_config()
        cfg["access_token"]  = access_token
        cfg["refresh_token"] = refresh_token
        CONFIG_FILE.write_text(json.dumps(cfg, indent=2, ensure_ascii=False))
        os.chmod(CONFIG_FILE, 0o600)
    except Exception as e:
        print(f"[save-tokens] {e}", file=sys.stderr)


# ── Global state ──────────────────────────────────────────────────────────────

_client = None
_state_lock = threading.Lock()
_refresh_gate = threading.Lock()   # serialises cloud sweeps (loop vs. /refresh)
_last_error: str | None = None
_last_refresh: float = 0
_location_name: str = ""

# OAuth helpers — set in main() after sys.path is ready
_exchange_code = None
_build_oauth_url = None

# OAuth flow state: pending while waiting for browser callback
_auth_state: dict = {"pending": False, "error": None}

# Motion sensor notification tracking: device_id → already-notified
_motion_alerted: set[str] = set()


def _notify(title: str, body: str) -> None:
    try:
        subprocess.run(
            ["notify-send", "-a", "SmartThings", "-i", "smartphone",
             "-u", "normal", "-t", "5000", title, body],
            check=False, timeout=3,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass


def _check_motion(devices: dict) -> None:
    """Fire a desktop notification when a motion sensor becomes active."""
    for did, dev in devices.items():
        if dev.get("type") != "sensor":
            continue
        motion = dev.get("state", {}).get("motion")
        if motion is True and did not in _motion_alerted:
            _notify("Movimiento detectado", dev.get("name", did))
            _motion_alerted.add(did)
        elif motion is False:
            _motion_alerted.discard(did)


def _refresh_now() -> dict:
    """Pull fresh state from the cloud and stamp _last_refresh.

    One sweep at a time: if the background loop is already mid-poll, wait for it
    and hand back its result rather than doubling the API traffic."""
    global _last_error, _last_refresh
    if not _refresh_gate.acquire(blocking=False):
        with _refresh_gate:
            return _client.devices
    try:
        devices = _client.fetch_devices()
        _check_motion(devices)
        _last_error = None
        _last_refresh = time.time()
        return devices
    finally:
        _refresh_gate.release()


def _refresh_loop():
    global _last_error
    while True:
        try:
            _refresh_now()
        except Exception as e:
            _last_error = str(e)
            print(f"[refresh] {e}", file=sys.stderr)
        time.sleep(POLL_INTERVAL)


# ── HTTP handler ──────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # silence default access log

    def _send_html(self, code: int, html: str):
        body = html.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, code: int, data, extra_headers: dict | None = None):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        for name, value in (extra_headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        if length:
            return json.loads(self.rfile.read(length))
        return {}

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path   = parsed.path.rstrip("/")
        query  = urllib.parse.parse_qs(parsed.query)

        # ── OAuth callback from browser ──────────────────────────────────
        if path == "/callback":
            code  = (query.get("code")  or [None])[0]
            error = (query.get("error") or [None])[0]
            if error or not code:
                _auth_state.update(pending=False, error=error or "no code recibido")
                self._send_html(400,
                    "<h2>Error de autorización</h2><p>Puedes cerrar esta ventana.</p>")
                return
            try:
                token_data = _exchange_code(code)
                cfg = load_config()
                cfg["access_token"]  = token_data["at"]
                cfg["refresh_token"] = token_data.get("rt", "")
                CONFIG_FILE.write_text(json.dumps(cfg, indent=2, ensure_ascii=False))
                os.chmod(CONFIG_FILE, 0o600)
                with _state_lock:
                    _client.access_token = cfg["access_token"]
                    _client.refresh_tok  = cfg["refresh_token"]
                try:
                    _client.fetch_devices()
                except Exception:
                    pass
                _auth_state.update(pending=False, error=None)
                self._send_html(200,
                    "<h2>✓ Autorización completada</h2>"
                    "<p>Puedes cerrar esta ventana y volver al widget.</p>")
            except Exception as e:
                _auth_state.update(pending=False, error=str(e))
                self._send_html(500, f"<h2>Error</h2><p>{e}</p>")
            return

        # ── Auth status (polled by config page) ──────────────────────────
        if path == "/auth/status":
            configured = False
            if CONFIG_FILE.exists():
                try:
                    configured = bool(load_config().get("access_token"))
                except Exception:
                    pass
            self._send_json(200, {
                "configured": configured,
                "location":   _location_name,
                "pending":    _auth_state["pending"],
                "error":      _auth_state["error"],
            })
            return

        if path == "/status":
            self._send_json(200, {
                "ok": _last_error is None,
                "error": _last_error,
                "last_refresh": _last_refresh,
                "device_count": len(_client.devices),
            })

        elif path == "/devices":
            aliases = _load_aliases()
            # The body is the cache; the header says how old the cloud read is,
            # so a client can show real freshness instead of "just re-read it".
            self._send_json(200,
                            [_with_aliases(d, aliases) for d in _client.devices.values()],
                            {"X-Last-Refresh": f"{_last_refresh:.3f}"})

        elif path == "/aliases":
            self._send_json(200, _load_aliases())

        elif path == "/channel_names":
            # Legacy shape: {device_id: [name per outlet]}, derived from aliases.
            out: dict[str, list] = {}
            for key, name in _load_aliases().items():
                did, _, idx = key.rpartition("_")
                if not did or not idx.isdigit():
                    continue
                names = out.setdefault(did, [])
                names.extend([""] * (int(idx) + 1 - len(names)))
                names[int(idx)] = name
            self._send_json(200, out)

        elif path.startswith("/devices/"):
            did = path[len("/devices/"):]
            dev = _client.devices.get(did)
            if dev:
                self._send_json(200, _with_aliases(dev, _load_aliases()))
            else:
                self._send_json(404, {"error": "device not found"})
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.rstrip("/")
        body = self._read_body()

        # /auth/start  → begin OAuth flow, return the authorization URL
        if path == "/auth/start":
            if _build_oauth_url is None:
                self._send_json(503, {"ok": False, "error": "daemon no inicializado"})
                return
            try:
                state = secrets.token_hex(8)
                _auth_state.update(pending=True, error=None, state=state)
                url = _build_oauth_url(state)
                self._send_json(200, {"ok": True, "url": url})
            except Exception as e:
                self._send_json(500, {"ok": False, "error": str(e)})
            return

        # /refresh  → force a cloud sweep now, instead of waiting for the loop
        if path == "/refresh":
            try:
                devices = _refresh_now()
                self._send_json(200, {"ok": True, "count": len(devices),
                                      "last_refresh": _last_refresh})
            except Exception as e:
                print(f"[refresh] {e}", file=sys.stderr)
                self._send_json(500, {"ok": False, "error": str(e)})
            return

        # /alias  → local rename of any device or channel ("" restores the original)
        if path == "/alias":
            key  = str(body.get("key", "")).strip()
            name = str(body.get("name", "")).strip()
            if not key:
                self._send_json(400, {"ok": False, "error": "key required"})
                return
            try:
                _set_alias(key, name)
                self._send_json(200, {"ok": True})
            except Exception as e:
                self._send_json(500, {"ok": False, "error": str(e)})
            return

        # /channel_name  → legacy shim: rename a single channel
        if path == "/channel_name":
            device_id = body.get("device_id", "")
            outlet    = body.get("outlet", -1)
            name      = body.get("name", "").strip()
            if not device_id or outlet < 0:
                self._send_json(400, {"ok": False, "error": "device_id and outlet required"})
                return
            try:
                _set_alias(f"{device_id}_{outlet}", name)
                self._send_json(200, {"ok": True})
            except Exception as e:
                self._send_json(500, {"ok": False, "error": str(e)})
            return

        # /channel_names  → legacy shim: save a whole channel name list
        if path == "/channel_names":
            device_id  = body.get("device_id", "")
            names_list = body.get("names", [])
            if not device_id or not isinstance(names_list, list):
                self._send_json(400, {"ok": False, "error": "device_id and names required"})
                return
            try:
                for i, name in enumerate(names_list):
                    _set_alias(f"{device_id}_{i}", str(name or "").strip())
                self._send_json(200, {"ok": True})
            except Exception as e:
                self._send_json(500, {"ok": False, "error": str(e)})
            return

        # /devices/{id}/on|off|toggle|brightness|lock|unlock
        parts = path.split("/")
        if len(parts) >= 4 and parts[1] == "devices":
            did    = parts[2]
            action = parts[3]
            dev = _client.devices.get(did)
            if not dev:
                self._send_json(404, {"error": "device not found"})
                return

            outlet = body.get("outlet")

            # Work out the optimistic patch + the cloud call up front, so we can
            # update the cache BEFORE the (~1 s) cloud round-trip. That way a
            # widget poll landing during the round-trip already sees the new
            # state and never bounces back to the old one.
            try:
                if action in ("on", "off"):
                    target = action == "on"
                    patch = {"on": target}
                    run = lambda: _client.set_switch(did, target, outlet)
                elif action == "toggle":
                    channels = dev["state"].get("channels")
                    if channels:
                        idx  = outlet if outlet is not None else 0
                        newv = not (channels[idx] if idx < len(channels) else False)
                        chans = list(channels)
                        if idx < len(chans):
                            chans[idx] = newv
                        patch = {"channels": chans}
                    else:
                        newv  = not dev["state"].get("on", False)
                        patch = {"on": newv}
                    run = lambda: _client.set_switch(did, newv, outlet)
                elif action == "brightness":
                    v = int(body.get("value", 100))
                    patch = {"brightness": v, "on": True}
                    run = lambda: _client.set_brightness(did, v)
                elif action == "lock":
                    patch = {"locked": True}
                    run = lambda: _client.set_lock(did, True)
                elif action == "unlock":
                    patch = {"locked": False}
                    run = lambda: _client.set_lock(did, False)
                elif action == "volume":
                    v = int(body.get("value", 0))
                    patch = {"volume": v}
                    run = lambda: _client.set_volume(did, v)
                elif action in ("play", "pause", "stop"):
                    patch = {"playback": {"play": "playing", "pause": "paused",
                                          "stop": "stopped"}[action]}
                    run = lambda: _client.media_command(did, action)
                elif action == "mode":
                    v = str(body.get("value", ""))
                    patch = {"mode": v}
                    run = lambda: _client.set_ac_mode(did, v)
                elif action == "setpoint":
                    v = int(body.get("value", 0))
                    patch = {"setpoint": v}
                    run = lambda: _client.set_ac_setpoint(did, v)
                else:
                    self._send_json(404, {"error": f"unknown action: {action}"})
                    return

                _client.patch_state(did, patch)  # optimistic, before the cloud call
                ok = run()
            except Exception as e:
                print(f"[control] {did} {action}: {e}", file=sys.stderr, flush=True)
                try:
                    _client.refresh_device(did)  # undo the optimistic guess
                except Exception:
                    pass
                self._send_json(500, {"ok": False, "error": str(e)})
                return

            if ok:
                # Reconcile with the real cloud state once SmartThings has caught
                # up, so a silently-failed command self-corrects.
                def _reconcile(device_id=did):
                    time.sleep(6)
                    try:
                        _client.refresh_device(device_id)
                    except Exception:
                        pass
                threading.Thread(target=_reconcile, daemon=True).start()
            else:
                # Command rejected: correct the optimistic cache right away.
                try:
                    _client.refresh_device(did)
                except Exception:
                    pass
            self._send_json(200 if ok else 500, {"ok": ok})
        else:
            self._send_json(404, {"error": "not found"})

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    global _client, _location_name
    from smartthings_api import (SmartThingsClient, set_credentials,
                                 set_refresh_mode, exchange_code, build_oauth_url)
    global _exchange_code, _build_oauth_url
    _exchange_code   = exchange_code
    _build_oauth_url = build_oauth_url

    cfg = load_config()
    set_credentials(cfg.get("client_id", ""), cfg.get("client_secret") or "")

    # Auth mode: "cli_bridge" borrows the SmartThings CLI's public client to
    # refresh tokens (the OAuth-In consent screen is currently broken server-side).
    # Falls back to our own OAuth-In app for refresh in the default "oauth" mode.
    if cfg.get("auth_mode") == "cli_bridge":
        set_refresh_mode("cli_bridge", cfg.get("cli_client_id", ""))
        print("Auth mode: cli_bridge (SmartThings CLI client)")

    _client = SmartThingsClient(
        access_token=cfg.get("access_token", ""),
        refresh_tok=cfg.get("refresh_token", ""),
    )
    _client.on_token_refresh = save_tokens

    print("Fetching devices…")
    try:
        devices = _client.fetch_devices()
        print(f"Found {len(devices)} devices")
    except Exception as e:
        print(f"Initial device fetch failed: {e}", file=sys.stderr)

    try:
        _location_name = _client.location_name()
    except Exception:
        pass

    t = threading.Thread(target=_refresh_loop, daemon=True)
    t.start()

    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"SmartThings daemon running on http://127.0.0.1:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopped.")


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).parent))
    main()
