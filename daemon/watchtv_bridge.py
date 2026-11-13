"""Bridge with watchtv (sends movies to the TV over DLNA / Cast).

The two projects see the same TVs from opposite sides: SmartThings through the
cloud — it can turn a TV on, but cannot hand it a file — and watchtv on the LAN,
where it can stream a file but cannot reach a TV that is off. Nothing here is
required by either side: watchtv only talks to this daemon if it is running,
and the widget only offers watchtv if it is installed.

What watchtv sends us:
  POST /watchtv/now   what is playing, every ~10 s and on every state change
  POST /events        failures (connection lost, recovery failed…) for the history

Names do not match exactly between the two worlds: the TV announces itself
over DLNA as "[TV] The Frame" while SmartThings calls it "The Frame". Both
sides normalise the same way (see `normalize`).
"""

import os
import re
import shutil
import threading
import time
from pathlib import Path

# watchtv reports every ~10 s while playing; three missed reports means it is
# gone (killed, laptop closed) even if it never said "stopped".
NOW_TTL = 35


def normalize(name: str) -> str:
    """'[TV] The Frame' → 'the frame'; '32" Smart Monitor M9' → '32 smart monitor m9'."""
    name = re.sub(r"^\s*\[[^\]]*\]\s*", "", name or "")
    name = re.sub(r"[^\w]+", " ", name.lower())
    return " ".join(name.split())


def match_tv(name: str, tvs: list) -> dict | None:
    """The SmartThings TV a DLNA/Cast name refers to, or None.

    Exact (normalised) first, against the local alias and the cloud name;
    then containment either way, but only when it is unambiguous."""
    want = normalize(name)
    if not want:
        return None
    for tv in tvs:
        if want in (normalize(tv.get("name", "")), normalize(tv.get("orig_name", ""))):
            return tv
    hits = []
    for tv in tvs:
        for n in (normalize(tv.get("name", "")), normalize(tv.get("orig_name", ""))):
            if len(n) >= 4 and len(want) >= 4 and (n in want or want in n):
                hits.append(tv)
                break
    return hits[0] if len(hits) == 1 else None


class NowPlaying:
    """What watchtv is playing, per SmartThings TV id. In memory only."""

    def __init__(self):
        self._lock = threading.Lock()
        self._by_tv: dict = {}

    def update(self, tv_id: str, data: dict) -> None:
        with self._lock:
            if data.get("state") == "stopped":
                self._by_tv.pop(tv_id, None)
            else:
                self._by_tv[tv_id] = {**data, "received": time.time()}

    def get(self, tv_id: str) -> dict | None:
        """Fresh entry with the position projected to now, or None."""
        with self._lock:
            entry = self._by_tv.get(tv_id)
            if not entry:
                return None
            age = time.time() - entry["received"]
            if age > NOW_TTL:
                self._by_tv.pop(tv_id, None)
                return None
            out = {k: v for k, v in entry.items() if k != "received"}
        # A report is up to 10 s old: while playing, the position moved on.
        if out.get("state") == "playing" and isinstance(out.get("position"), (int, float)):
            pos = out["position"] + age
            dur = out.get("duration") or 0
            out["position"] = min(pos, dur) if dur else pos
        return out


def gui_path() -> str:
    """Absolute path of watchtv-gui, or "" if it is not installed.

    The daemon runs under systemd, whose PATH usually lacks ~/.local/bin —
    which is exactly where watchtv's installer puts its links."""
    found = shutil.which("watchtv-gui")
    if found:
        return found
    local = Path.home() / ".local" / "bin" / "watchtv-gui"
    return str(local) if local.exists() and os.access(local, os.X_OK) else ""
