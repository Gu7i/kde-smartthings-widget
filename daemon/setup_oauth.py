#!/usr/bin/env python3
"""
Setup OAuth2 — abre el navegador para autorizar la SmartApp en SmartThings,
captura el código de retorno y lo intercambia por tokens.
"""

import json
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

CONFIG_DIR    = Path.home() / ".config" / "smartthings-widget"
CONFIG_FILE   = CONFIG_DIR / "config.json"
CALLBACK_PORT = 7182

sys.path.insert(0, str(Path(__file__).parent))
from smartthings_api import (
    set_credentials, build_oauth_url, exchange_code, SmartThingsClient, SCOPES,
)

# ── Callback HTTP server ──────────────────────────────────────────────────────

_auth_code: str | None = None
_auth_error: str | None = None
_done = threading.Event()


class CallbackHandler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass

    def do_GET(self):
        global _auth_code, _auth_error
        params = parse_qs(urlparse(self.path).query)

        if "code" in params:
            _auth_code = params["code"][0]
            msg = b"<h2>Autorizado. Puedes cerrar esta ventana.</h2>"
        elif "error" in params:
            _auth_error = params.get("error_description", ["error desconocido"])[0]
            msg = f"<h2>Error: {_auth_error}</h2>".encode()
        else:
            msg = b"<h2>Esperando...</h2>"

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(msg)
        _done.set()


def _start_callback_server() -> HTTPServer:
    server = HTTPServer(("127.0.0.1", CALLBACK_PORT), CallbackHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("=== SmartThings Widget Setup ===\n")

    if CONFIG_FILE.exists():
        with open(CONFIG_FILE) as f:
            existing = json.load(f)
        print(f"Config existente (client_id: {existing.get('client_id', '?')[:8]}…)")
        if input("¿Sobreescribir? [s/N] ").strip().lower() not in ("s", "y"):
            sys.exit(0)

    # ── Credenciales de la SmartApp ───────────────────────────────────────────
    print("── Credenciales de la SmartApp OAuth (SmartThings CLI) ─────────")
    print("Crea una con:  smartthings apps:create   (tipo OAuth-In)")
    print(f"Redirect URI: http://localhost:{CALLBACK_PORT}/callback")
    print(f"Scopes:       {' '.join(SCOPES)}\n")
    client_id     = input("Client ID    : ").strip()
    client_secret = input("Client Secret: ").strip()
    set_credentials(client_id, client_secret)

    # ── OAuth2 flow ───────────────────────────────────────────────────────────
    print("\n── Autorización OAuth2 ─────────────────────────────────────────")
    print("Se abrirá el navegador para iniciar sesión en SmartThings.")
    print("Después de autorizar, volverá automáticamente aquí.\n")

    server    = _start_callback_server()
    oauth_url = build_oauth_url("smartthings-kde-widget")
    print(f"Abriendo: {oauth_url[:80]}…\n")
    webbrowser.open(oauth_url)

    print("Esperando autorización en el navegador… (timeout: 120s)")
    _done.wait(timeout=120)
    server.shutdown()

    if _auth_error:
        print(f"\nError de autorización: {_auth_error}")
        sys.exit(1)
    if not _auth_code:
        print("\nTimeout — no se recibió respuesta del navegador.")
        print("Si el navegador no abrió, ve a esta URL manualmente:")
        print(oauth_url)
        sys.exit(1)

    print("Código recibido. Intercambiando por token…")
    try:
        token_data = exchange_code(_auth_code)
    except Exception as e:
        print(f"\nError al obtener el token: {e}")
        sys.exit(1)

    access_token = token_data["at"]
    refresh_tok  = token_data.get("rt", "")

    # ── Verificar listando dispositivos ──────────────────────────────────────
    client = SmartThingsClient(access_token, refresh_tok)
    try:
        devices = client.fetch_devices()
    except Exception as e:
        print(f"\nError al obtener dispositivos: {e}")
        sys.exit(1)

    print(f"\nLogin OK — {len(devices)} dispositivos encontrados:\n")
    icons = {"switch": "🔌", "multi_switch": "🔌🔌", "sensor": "🌡️",
             "dimmer": "💡", "lock": "🔒", "button": "🔘", "hub": "📡"}
    for dev in sorted(devices.values(), key=lambda d: d["name"]):
        icon   = icons.get(dev["type"], "?")
        status = "online" if dev["online"] else "offline"
        print(f"  {icon}  {dev['name']:30s}  [{dev['type']}]  {status}")

    # ── Guardar config ────────────────────────────────────────────────────────
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    cfg = {
        "client_id":     client_id,
        "client_secret": client_secret,
        "access_token":  access_token,
        "refresh_token": refresh_tok,
    }
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)
    CONFIG_FILE.chmod(0o600)

    print(f"\nConfiguración guardada en {CONFIG_FILE}")
    print("Inicia el daemon con:  python3 smartthings_service.py")


if __name__ == "__main__":
    main()
