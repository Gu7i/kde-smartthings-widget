#!/usr/bin/env python3
"""
Setup (cli_bridge) — bootstraps the widget from your SmartThings CLI login.

Since Dec 2024 SmartThings Personal Access Tokens expire after 24 h, and the
OAuth-In consent screen is currently unreliable server-side. So instead the
widget borrows the SmartThings CLI's login: the CLI signs you in with a public
OAuth client that issues a refreshable token (scope `controller:stCli`, which
can read *and* control devices). This script copies that token into the widget
config; the daemon then refreshes it itself, forever, with no browser consent.

Prerequisites (one-time):
    npm install -g @smartthings/cli
    smartthings login          # opens the browser, signs in to your account

Then just run:  python3 setup.py
"""

import datetime
import json
import sys
from pathlib import Path

CLI_CREDS   = Path.home() / ".config" / "@smartthings" / "cli" / "credentials.json"
CONFIG_DIR  = Path.home() / ".config" / "smartthings-widget"
CONFIG_FILE = CONFIG_DIR / "config.json"

# Public PKCE OAuth client of @smartthings/cli (no secret). Used to refresh the
# borrowed token against auth-global. Found in @smartthings/cli-lib.
CLI_CLIENT_ID = "d18cf96e-c626-4433-bf51-ddbb10c5d1ed"
REFRESH_URL   = "https://auth-global.api.smartthings.com/oauth/token"

sys.path.insert(0, str(Path(__file__).parent))
from smartthings_api import set_refresh_mode, refresh_token, SmartThingsClient


def _fail(msg: str) -> None:
    print(msg)
    sys.exit(1)


def main() -> None:
    print("=== SmartThings Widget — setup (cli_bridge) ===\n")

    if not CLI_CREDS.exists():
        _fail(
            "No encuentro las credenciales del SmartThings CLI en:\n"
            f"  {CLI_CREDS}\n\n"
            "Instala el CLI e inicia sesión primero:\n"
            "  npm install -g @smartthings/cli\n"
            "  smartthings login\n"
        )

    creds     = json.load(open(CLI_CREDS))
    prof_name = "default" if "default" in creds else next(iter(creds), None)
    prof      = creds.get(prof_name) if prof_name else None
    if not prof or not prof.get("refreshToken"):
        _fail("El CLI no tiene un refresh token. Corre:  smartthings login")

    # Refresh the borrowed token (rotates it) to confirm it works and get a
    # fresh access token.
    set_refresh_mode("cli_bridge", CLI_CLIENT_ID)
    print("Refrescando el token del SmartThings CLI…")
    try:
        tok = refresh_token(prof["refreshToken"])
    except Exception as e:
        _fail(f"Error al refrescar el token: {e}\nVuelve a iniciar sesión: smartthings login")

    at, rt = tok["at"], tok["rt"]
    exp = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=86400)
    exp_iso = exp.strftime("%Y-%m-%dT%H:%M:%S.") + f"{exp.microsecond // 1000:03d}Z"

    # Refresh tokens rotate on use — write the new one back so the CLI keeps
    # working too.
    prof.update(accessToken=at, refreshToken=rt, expires=exp_iso)
    creds[prof_name] = prof
    CLI_CREDS.write_text(json.dumps(creds, indent=4))
    CLI_CREDS.chmod(0o600)

    # Verify by listing devices.
    client = SmartThingsClient(at, rt)
    try:
        devices = client.fetch_devices()
    except Exception as e:
        _fail(f"Error al listar dispositivos: {e}")

    print(f"\nLogin OK — {len(devices)} dispositivos encontrados:\n")
    icons = {"switch": "🔌", "multi_switch": "🔌", "dimmer": "💡", "sensor": "🌡️",
             "lock": "🔒", "button": "🔘", "hub": "📡", "tv": "📺", "ac": "❄️",
             "speaker": "🔊", "appliance": "🧺"}
    for dev in sorted(devices.values(), key=lambda d: d["name"]):
        icon   = icons.get(dev["type"], "•")
        status = "online" if dev["online"] else "offline"
        print(f"  {icon}  {dev['name']:30s}  [{dev['type']}]  {status}")

    # Save the widget config.
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    cfg = {
        "auth_mode":     "cli_bridge",
        "cli_client_id": CLI_CLIENT_ID,
        "refresh_url":   REFRESH_URL,
        "access_token":  at,
        "refresh_token": rt,
        "token_expires": exp_iso,
    }
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2))
    CONFIG_FILE.chmod(0o600)

    print(f"\nConfiguración guardada en {CONFIG_FILE}")
    print("Inicia el daemon con:")
    print("  systemctl --user enable --now smartthings-daemon.service")


if __name__ == "__main__":
    main()
