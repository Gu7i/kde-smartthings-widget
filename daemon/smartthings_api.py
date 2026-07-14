"""SmartThings Cloud API — OAuth2 Authorization Code flow.

SmartThings has a single global endpoint (no regions) and a clean,
capability-based device model. Authentication is standard OAuth2:

    setup.py  → browser authorization → access_token + refresh_token
    daemon    → refreshes the access_token automatically (tokens last 24h,
                refresh tokens rotate on every use and must be persisted).
"""

import base64
import json
import threading
import time
import urllib.request
import urllib.parse
import urllib.error

API_BASE      = "https://api.smartthings.com"
# User authorization is served from account.smartthings.com (api.smartthings.com
# returns an ELB 403 for /oauth/authorize). Token exchange stays on api.
AUTHORIZE_URL = "https://account.smartthings.com/oauth/authorize"
TOKEN_URL     = "https://api.smartthings.com/oauth/token"
REDIRECT_URL  = "http://localhost:7182/callback"

# Scopes: read + control devices. (Matches the set the SmartThings CLI itself
# requests for OAuth-In apps; adding r:locations:* triggers an authorize error.)
SCOPES = ["r:devices:*", "w:devices:*", "x:devices:*"]

# Filled at runtime from config via set_credentials()
CLIENT_ID     = ""
CLIENT_SECRET = ""

# ── Refresh mode ──────────────────────────────────────────────────────────────
# Two ways to refresh the access token:
#   • "oauth"      → our own OAuth-In app: POST api.smartthings.com/oauth/token
#                    with HTTP Basic (client_id:client_secret).
#   • "cli_bridge" → reuse the SmartThings CLI's public PKCE client. The CLI logs
#                    in with a global client and refreshes against auth-global with
#                    just the (public) client_id — no secret. We borrow its rotating
#                    refresh token so the widget stays authenticated without the
#                    (currently broken) consent screen. Scope: controller:stCli.
CLI_REFRESH_URL       = "https://auth-global.api.smartthings.com/oauth/token"
REFRESH_URL_ACTIVE    = TOKEN_URL   # overridden by set_refresh_mode()
REFRESH_USE_BASIC     = True        # oauth mode uses Basic auth
REFRESH_CLIENT_ID     = ""          # public client id in cli_bridge mode


def set_refresh_mode(mode: str, client_id: str = "") -> None:
    """Configure how refresh_token() talks to the token endpoint."""
    global REFRESH_URL_ACTIVE, REFRESH_USE_BASIC, REFRESH_CLIENT_ID
    if mode == "cli_bridge":
        REFRESH_URL_ACTIVE = CLI_REFRESH_URL
        REFRESH_USE_BASIC  = False
        REFRESH_CLIENT_ID  = client_id
    else:
        REFRESH_URL_ACTIVE = TOKEN_URL
        REFRESH_USE_BASIC  = True
        REFRESH_CLIENT_ID  = ""

# ── Capability → widget type mapping ──────────────────────────────────────────
LOCK_CAPS   = {"lock"}
DIMMER_CAPS = {"switchLevel"}
BUTTON_CAPS = {"button"}
SENSOR_CAPS = {"motionSensor", "contactSensor", "temperatureMeasurement",
               "relativeHumidityMeasurement", "presenceSensor", "waterSensor",
               "illuminanceMeasurement", "smokeDetector", "carbonMonoxideDetector"}

# ── Component category → widget type mapping ──────────────────────────────────
# SmartThings tags each device component with categories (the same signal its
# own app uses for grouping/icons). These take priority over capability guessing
# so e.g. a TV or AC — which also expose a `switch` — isn't filed under lights.
TV_CATS        = {"Television", "SmartMonitor", "SetTopBox", "Projector", "Tv"}
CLIMATE_CATS   = {"AirConditioner", "Thermostat", "AirPurifier", "Heater",
                  "Fan", "Humidifier", "Dehumidifier"}
SPEAKER_CATS   = {"Speaker", "NetworkAudio", "Receiver", "SoundBar"}
APPLIANCE_CATS = {"Washer", "Dryer", "Dishwasher", "Refrigerator", "Oven",
                  "MicrowaveOven", "RobotCleaner", "CoffeeMaker", "CooktopHob",
                  "Vacuum"}


def set_credentials(client_id: str, client_secret: str) -> None:
    global CLIENT_ID, CLIENT_SECRET
    CLIENT_ID     = client_id
    CLIENT_SECRET = client_secret


# ── Low-level HTTP ────────────────────────────────────────────────────────────

def _http(method: str, url: str, *, token: str | None = None,
          form: dict | None = None, json_body: dict | None = None,
          basic: bool = False) -> tuple[int, dict]:
    """Perform an HTTP request. Returns (status_code, parsed_json)."""
    headers = {"Accept": "application/json"}
    data = None

    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    elif json_body is not None:
        data = json.dumps(json_body).encode()
        headers["Content-Type"] = "application/json"

    if basic:
        cred = base64.b64encode(f"{CLIENT_ID}:{CLIENT_SECRET}".encode()).decode()
        headers["Authorization"] = f"Basic {cred}"
    elif token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"error": raw.decode(errors="replace")}


# ── OAuth2 helpers ────────────────────────────────────────────────────────────

def build_oauth_url(state: str) -> str:
    """Build the URL to open in the browser for user authorization."""
    params = {
        "client_id":     CLIENT_ID,
        "response_type": "code",
        "redirect_uri":  REDIRECT_URL,
        "scope":         " ".join(SCOPES),
        "state":         state,
    }
    return f"{AUTHORIZE_URL}?{urllib.parse.urlencode(params)}"


def exchange_code(code: str) -> dict:
    """Exchange the OAuth2 authorization code for access + refresh tokens."""
    status, data = _http(
        "POST", TOKEN_URL,
        form={
            "grant_type":   "authorization_code",
            "code":         code,
            "client_id":    CLIENT_ID,
            "redirect_uri": REDIRECT_URL,
        },
        basic=True,
    )
    if status != 200 or "access_token" not in data:
        raise RuntimeError(f"Token exchange failed ({status}): {data}")
    return {
        "at": data["access_token"],
        "rt": data.get("refresh_token", ""),
    }


def refresh_token(refresh_tok: str) -> dict:
    """Get a new access token using the (rotating) refresh token."""
    status, data = _http(
        "POST", REFRESH_URL_ACTIVE,
        form={
            "grant_type":    "refresh_token",
            "refresh_token": refresh_tok,
            "client_id":     REFRESH_CLIENT_ID or CLIENT_ID,
        },
        basic=REFRESH_USE_BASIC,
    )
    if status != 200 or "access_token" not in data:
        raise RuntimeError(f"Token refresh failed ({status}): {data}")
    return {
        "at": data["access_token"],
        "rt": data.get("refresh_token", refresh_tok),
    }


# ── Main API client ───────────────────────────────────────────────────────────

class SmartThingsClient:
    def __init__(self, access_token: str, refresh_tok: str = ""):
        self.access_token = access_token
        self.refresh_tok  = refresh_tok
        self._devices: dict = {}
        self._lock          = threading.Lock()
        self._refresh_lock       = threading.Lock()
        self._last_token_refresh = 0.0
        # device_id → time until which polls keep the optimistic state instead of
        # overwriting it with a (possibly not-yet-updated) cloud read.
        self._hold: dict = {}
        # Called with (access_token, refresh_token) whenever tokens rotate,
        # so the daemon can persist them to config.
        self.on_token_refresh = None

    # ── Authenticated requests with transparent token refresh ────────────────

    def _get(self, path: str) -> dict:
        status, data = _http("GET", f"{API_BASE}{path}", token=self.access_token)
        if status == 401 and self.refresh_tok:
            self._ensure_token()
            status, data = _http("GET", f"{API_BASE}{path}", token=self.access_token)
        if status >= 400:
            raise RuntimeError(f"GET {path} → {status}: {data}")
        return data

    def _post(self, path: str, body: dict) -> dict:
        status, data = _http("POST", f"{API_BASE}{path}",
                             token=self.access_token, json_body=body)
        if status == 401 and self.refresh_tok:
            self._ensure_token()
            status, data = _http("POST", f"{API_BASE}{path}",
                                 token=self.access_token, json_body=body)
        if status >= 400:
            raise RuntimeError(f"POST {path} → {status}: {data}")
        return data

    def _ensure_token(self) -> None:
        if not self.refresh_tok:
            return
        with self._refresh_lock:
            # A concurrent request may have already refreshed while we waited on
            # the lock — refresh tokens rotate, so avoid a double refresh that
            # would invalidate the freshly-issued one.
            if time.time() - self._last_token_refresh < 10:
                return
            data = refresh_token(self.refresh_tok)
            self.access_token = data["at"]
            self.refresh_tok  = data.get("rt", self.refresh_tok)
            self._last_token_refresh = time.time()
            if self.on_token_refresh:
                self.on_token_refresh(self.access_token, self.refresh_tok)

    # ── Account info ─────────────────────────────────────────────────────────

    def location_name(self) -> str:
        try:
            data = self._get("/v1/locations")
            items = data.get("items", [])
            if items:
                return items[0].get("name", "")
        except Exception:
            pass
        return ""

    # ── Devices ──────────────────────────────────────────────────────────────

    def fetch_devices(self) -> dict:
        result = self._get("/v1/devices")
        devices = {}
        for dev in result.get("items", []):
            did   = dev["deviceId"]
            label = dev.get("label") or dev.get("name") or did

            comp_caps: dict[str, list[str]] = {}
            switch_components: list[str] = []
            all_caps: set[str] = set()
            categories: set[str] = set()
            for comp in dev.get("components", []):
                cid  = comp.get("id", "main")
                caps = [c["id"] for c in comp.get("capabilities", [])]
                comp_caps[cid] = caps
                all_caps.update(caps)
                for cat in comp.get("categories", []):
                    if cat.get("name"):
                        categories.add(cat["name"])
                if "switch" in caps:
                    switch_components.append(cid)

            devices[did] = {
                "id":                did,
                "name":              label,
                "type":              _device_type(dev.get("type", ""), all_caps,
                                                  switch_components, categories),
                "online":            True,
                "components":        comp_caps,
                "switch_components": switch_components,
                "categories":        sorted(categories),
                "state":             {},
            }

        # Fetch per-device status + health (SmartThings has no bulk status endpoint).
        old = self.devices           # locked snapshot of the previous cache
        now = time.time()
        for did, dev in devices.items():
            # Within the optimistic hold window after a command, keep the cached
            # state so a poll doesn't clobber it with a stale cloud read.
            if self._hold.get(did, 0) > now and did in old:
                dev["state"]  = dict(old[did].get("state", {}))
                dev["online"] = old[did].get("online", True)
                continue
            try:
                status = self._get(f"/v1/devices/{did}/status")
                dev["state"] = _extract_state(dev, status)
            except Exception as exc:
                print(f"[status] {did}: {exc}", flush=True)
            try:
                health = self._get(f"/v1/devices/{did}/health")
                dev["online"] = health.get("state") == "ONLINE"
            except Exception:
                pass

        with self._lock:
            self._devices = devices
        return devices

    def refresh_device(self, device_id: str) -> None:
        """Re-fetch a single device's status (cheap: ~1 request vs. a full poll).

        This is the deliberate post-command reconcile: it applies the real cloud
        state and clears the optimistic hold, so it always wins over the patch."""
        dev = self._devices.get(device_id)
        if not dev:
            return
        try:
            status = self._get(f"/v1/devices/{device_id}/status")
            new_state = _extract_state(dev, status)
            with self._lock:
                if device_id in self._devices:
                    self._devices[device_id]["state"] = new_state
                self._hold.pop(device_id, None)
        except Exception as exc:
            print(f"[status] {device_id}: {exc}", flush=True)

    def patch_state(self, device_id: str, patch: dict, hold: float = 6.0) -> None:
        """Merge an optimistic state patch into the cache so the widget's
        immediate re-read reflects the commanded state, and hold off polls from
        overwriting it for `hold` seconds (the real cloud state is reconciled
        after that, once SmartThings has caught up)."""
        with self._lock:
            dev = self._devices.get(device_id)
            if dev:
                dev["state"] = {**dev.get("state", {}), **patch}
                self._hold[device_id] = time.time() + hold

    @property
    def devices(self) -> dict:
        with self._lock:
            return dict(self._devices)

    # ── Commands ─────────────────────────────────────────────────────────────

    def _command(self, device_id: str, component: str, capability: str,
                 command: str, arguments: list | None = None) -> bool:
        body = {"commands": [{
            "component":  component,
            "capability": capability,
            "command":    command,
            "arguments":  arguments or [],
        }]}
        data = self._post(f"/v1/devices/{device_id}/commands", body)
        results = data.get("results", [])
        return bool(results) and results[0].get("status") in ("ACCEPTED", "COMPLETED")

    def _component_for_outlet(self, device_id: str, outlet) -> str:
        dev  = self._devices.get(device_id, {})
        comps = dev.get("switch_components") or ["main"]
        if outlet is None:
            return comps[0] if comps else "main"
        try:
            return comps[int(outlet)]
        except (ValueError, IndexError, TypeError):
            return "main"

    def set_switch(self, device_id: str, on: bool, outlet=None) -> bool:
        component = self._component_for_outlet(device_id, outlet)
        return self._command(device_id, component, "switch",
                             "on" if on else "off")

    def set_brightness(self, device_id: str, brightness: int) -> bool:
        level = max(1, min(100, brightness))
        return self._command(device_id, "main", "switchLevel", "setLevel", [level])

    def set_lock(self, device_id: str, locked: bool) -> bool:
        return self._command(device_id, "main", "lock",
                             "lock" if locked else "unlock")

    # ── Media (TV / speaker) ─────────────────────────────────────────────────
    def set_volume(self, device_id: str, volume: int) -> bool:
        v = max(0, min(100, int(volume)))
        return self._command(device_id, "main", "audioVolume", "setVolume", [v])

    def media_command(self, device_id: str, command: str) -> bool:
        if command not in ("play", "pause", "stop"):
            return False
        return self._command(device_id, "main", "mediaPlayback", command)

    # ── Climate (air conditioner) ────────────────────────────────────────────
    def set_ac_mode(self, device_id: str, mode: str) -> bool:
        return self._command(device_id, "main", "airConditionerMode",
                             "setAirConditionerMode", [mode])

    def set_ac_setpoint(self, device_id: str, temp: float) -> bool:
        return self._command(device_id, "main", "thermostatCoolingSetpoint",
                             "setCoolingSetpoint", [int(temp)])


# ── Helpers ───────────────────────────────────────────────────────────────────

def _device_type(raw_type: str, caps: set[str], switch_components: list[str],
                 categories: set[str]) -> str:
    if raw_type == "HUB" or "Hub" in categories:
        return "hub"
    if caps & LOCK_CAPS:
        return "lock"
    # Category-driven types first: these devices also expose `switch`, so without
    # this a TV/AC/washer/speaker would be misfiled as a plain light switch.
    if categories & TV_CATS:
        return "tv"
    if categories & CLIMATE_CATS:
        return "ac"
    if categories & SPEAKER_CATS:
        return "speaker"
    if categories & APPLIANCE_CATS:
        return "appliance"
    # Generic lights / switches / plugs
    if caps & DIMMER_CAPS:
        return "dimmer"
    if len(switch_components) > 1:
        return "multi_switch"
    if "switch" in caps:
        return "switch"
    if caps & BUTTON_CAPS or "RemoteController" in categories:
        return "button"
    if caps & SENSOR_CAPS:
        return "sensor"
    return "sensor"  # read-only fallback


def _cap_value(status: dict, component: str, capability: str, attribute: str):
    try:
        return status["components"][component][capability][attribute]["value"]
    except (KeyError, TypeError):
        return None


def _extract_state(dev: dict, status: dict) -> dict:
    dtype = dev["type"]
    main  = "main"

    battery = _cap_value(status, main, "battery", "battery")

    if dtype == "lock":
        lock_val = _cap_value(status, main, "lock", "lock")
        return {
            "locked":  (lock_val == "locked") if lock_val is not None else None,
            "battery": battery,
        }

    if dtype == "hub":
        return {"sub_devices": 0, "ip": ""}

    if dtype == "button":
        return {"key": 0, "battery": battery}

    if dtype == "tv":
        return {
            "on":       _cap_value(status, main, "switch", "switch") == "on",
            "volume":   _cap_value(status, main, "audioVolume", "volume"),
            "playback": _cap_value(status, main, "mediaPlayback", "playbackStatus") or "",
            "input":    _cap_value(status, main, "mediaInputSource", "inputSource") or "",
        }

    if dtype == "speaker":
        track = _cap_value(status, main, "audioTrackData", "audioTrackData") or {}
        title = ""
        if isinstance(track, dict):
            title = track.get("title") or track.get("mediaSource") or ""
        return {
            "playback": _cap_value(status, main, "mediaPlayback", "playbackStatus") or "",
            "volume":   _cap_value(status, main, "audioVolume", "volume"),
            "title":    title,
        }

    if dtype == "ac":
        sp    = _cap_value(status, main, "thermostatCoolingSetpoint", "coolingSetpoint")
        rng   = _cap_value(status, main, "thermostatCoolingSetpoint", "coolingSetpointRange") or {}
        modes = _cap_value(status, main, "airConditionerMode", "supportedAcModes") or []
        temp  = _cap_value(status, main, "temperatureMeasurement", "temperature")
        hum   = _cap_value(status, main, "relativeHumidityMeasurement", "humidity")
        return {
            "on":          _cap_value(status, main, "switch", "switch") == "on",
            "setpoint":    sp,
            "sp_min":      rng.get("minimum", 16) if isinstance(rng, dict) else 16,
            "sp_max":      rng.get("maximum", 30) if isinstance(rng, dict) else 30,
            "sp_step":     rng.get("step", 1) if isinstance(rng, dict) else 1,
            "mode":        _cap_value(status, main, "airConditionerMode", "airConditionerMode") or "",
            "modes":       modes if isinstance(modes, list) else [],
            "temperature": round(float(temp), 1) if temp is not None else None,
            "humidity":    round(float(hum)) if hum is not None else None,
        }

    if dtype == "appliance":
        mstate = (_cap_value(status, main, "washerOperatingState", "machineState")
                  or _cap_value(status, main, "dryerOperatingState", "machineState")
                  or _cap_value(status, main, "dishwasherOperatingState", "machineState") or "")
        jstate = (_cap_value(status, main, "washerOperatingState", "washerJobState")
                  or _cap_value(status, main, "dryerOperatingState", "dryerJobState") or "")
        return {
            "on":            _cap_value(status, main, "switch", "switch") == "on",
            "machine_state": mstate,
            "job_state":     jstate,
            "battery":       battery,
        }

    if dtype == "sensor":
        temp   = _cap_value(status, main, "temperatureMeasurement", "temperature")
        hum    = _cap_value(status, main, "relativeHumidityMeasurement", "humidity")
        motion = _cap_value(status, main, "motionSensor", "motion")
        contact = _cap_value(status, main, "contactSensor", "contact")
        state = {"battery": battery}
        if temp is not None:
            state["temperature"] = round(float(temp), 1)
        if hum is not None:
            state["humidity"] = round(float(hum))
        if motion is not None:
            state["motion"] = (motion == "active")
        elif contact is not None:
            # Represent an open contact like "motion" so the UI shows activity.
            state["motion"] = (contact == "open")
        return state

    if dtype == "dimmer":
        sw    = _cap_value(status, main, "switch", "switch")
        level = _cap_value(status, main, "switchLevel", "level")
        return {"on": sw == "on", "brightness": level if level is not None else 100}

    if dtype == "multi_switch":
        channels = []
        for cid in dev.get("switch_components", []):
            sw = _cap_value(status, cid, "switch", "switch")
            channels.append(sw == "on")
        return {"channels": channels}

    # single switch
    return {"on": _cap_value(status, main, "switch", "switch") == "on"}
