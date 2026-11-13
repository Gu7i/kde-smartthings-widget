"""Event history — what happened to each device, kept for diagnosis.

The daemon used to print cloud errors to the journal and forget them, so the
only trace of a TV that answered 500 forty times a day was a log nobody reads.
This keeps a bounded history the widget can show, with failures marked.

Storage is append-only JSON Lines under $XDG_STATE_HOME (state, not config:
losing it costs nothing but history). Every event has an `id`; a repeat of
the same thing is folded into the existing event (count + last_ts) and the
updated event is appended again with the same id — on load, the last line for
an id wins. When the file grows past MAX_FILE_BYTES it is rewritten from
memory, which drops both the superseded lines and anything past MAX_EVENTS.
"""

import json
import os
import re
import sys
import threading
import time
from collections import deque
from pathlib import Path

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state") \
            / "smartthings-widget"
EVENTS_FILE    = STATE_DIR / "events.jsonl"
MAX_EVENTS     = 2000
MAX_FILE_BYTES = 1_000_000

LEVELS = ("info", "warn", "error")

# A device that fails every sweep (20 s) would otherwise write ~4000 identical
# events a day. Within this window, the same failure becomes one event with a
# count — which is also the more useful reading: "x37 since 09:12".
COALESCE_WINDOW = 3600

# Request ids differ on every call; leaving them in would make every repeat of
# the same failure look new to the coalescer.
_REQUEST_ID = re.compile(r"'requestId':\s*'[^']*',?\s*")


class EventLog:
    def __init__(self, path: Path = EVENTS_FILE):
        self.path = path
        self._lock = threading.Lock()
        self._events: deque = deque(maxlen=MAX_EVENTS)
        self._by_id: dict = {}
        self._next_id = 1
        self._load()

    # ── Persistence ───────────────────────────────────────────────────────────

    def _load(self) -> None:
        if not self.path.exists():
            return
        latest: dict = {}
        try:
            with open(self.path, encoding="utf-8") as f:
                for line in f:
                    try:
                        ev = json.loads(line)
                    except ValueError:
                        continue            # a torn last line after a crash
                    if isinstance(ev, dict) and isinstance(ev.get("id"), int):
                        latest[ev["id"]] = ev
        except OSError as e:
            print(f"[events] {e}", file=sys.stderr)
            return
        for eid in sorted(latest)[-MAX_EVENTS:]:
            self._push(latest[eid])
        if latest:
            self._next_id = max(latest) + 1

    def _push(self, ev: dict) -> None:
        if len(self._events) == self._events.maxlen:
            self._by_id.pop(self._events[0]["id"], None)
        self._events.append(ev)
        self._by_id[ev["id"]] = ev

    def _append(self, ev: dict) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            if self.path.exists() and self.path.stat().st_size > MAX_FILE_BYTES:
                self._compact()
            with open(self.path, "a", encoding="utf-8") as f:
                f.write(json.dumps(ev, ensure_ascii=False) + "\n")
        except OSError as e:
            print(f"[events] {e}", file=sys.stderr)

    def _compact(self) -> None:
        tmp = self.path.with_suffix(".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            for ev in self._events:
                f.write(json.dumps(ev, ensure_ascii=False) + "\n")
        tmp.replace(self.path)

    # ── Writing ───────────────────────────────────────────────────────────────

    def add(self, level: str, kind: str, message: str, *,
            device_id: str = "", device_name: str = "",
            detail: str = "", key: str = "",
            window: float = COALESCE_WINDOW) -> dict:
        """Record an event. With a `key`, a matching event younger than `window`
        is updated (count, last_ts, latest message) instead of adding a row.

        kind: state | command | cloud | connectivity | daemon"""
        if level not in LEVELS:
            level = "info"
        detail = _REQUEST_ID.sub("", detail) if key else detail
        now = time.time()
        with self._lock:
            if key:
                for ev in reversed(self._events):
                    if ev.get("key") != key or ev.get("device_id") != device_id:
                        continue
                    if now - ev["last_ts"] <= window:
                        ev["count"]   += 1
                        ev["last_ts"]  = now
                        ev["message"]  = message
                        if detail:
                            ev["detail"] = detail
                        self._append(ev)
                        return ev
                    break                   # the matching one is too old
            ev = {
                "id":          self._next_id,
                "ts":          now,
                "last_ts":     now,
                "count":       1,
                "level":       level,
                "kind":        kind,
                "device_id":   device_id,
                "device_name": device_name,
                "message":     message,
                "detail":      detail,
                "key":         key,
            }
            self._next_id += 1
            self._push(ev)
            self._append(ev)
            return ev

    def clear(self) -> None:
        with self._lock:
            self._events.clear()
            self._by_id.clear()
            try:
                self.path.unlink(missing_ok=True)
            except OSError as e:
                print(f"[events] {e}", file=sys.stderr)

    # ── Reading ───────────────────────────────────────────────────────────────

    def query(self, *, device_id: str = "", min_level: str = "info",
              since: float = 0, limit: int = 300) -> list:
        """Newest first. `since` filters on last_ts, so a folded event that is
        still recurring counts as recent."""
        floor = LEVELS.index(min_level) if min_level in LEVELS else 0
        out = []
        with self._lock:
            for ev in reversed(self._events):
                if device_id and ev["device_id"] != device_id:
                    continue
                if LEVELS.index(ev["level"]) < floor:
                    continue
                if ev["last_ts"] < since:
                    continue
                out.append(dict(ev))
                if len(out) >= limit:
                    break
        out.sort(key=lambda e: e["last_ts"], reverse=True)
        return out

    def summary(self, hours: float = 24) -> dict:
        """Per device: warnings and errors in the window (folded counts
        included), plus the latest one — the "which device is sick" view."""
        since = time.time() - hours * 3600
        out: dict = {}
        with self._lock:
            for ev in self._events:
                if ev["level"] == "info" or ev["last_ts"] < since:
                    continue
                did = ev["device_id"] or "_daemon"
                row = out.setdefault(did, {"device_id": ev["device_id"],
                                           "device_name": ev["device_name"],
                                           "errors": 0, "warnings": 0,
                                           "last_ts": 0, "last_message": ""})
                row["errors" if ev["level"] == "error" else "warnings"] += ev["count"]
                if ev["last_ts"] >= row["last_ts"]:
                    row["last_ts"]      = ev["last_ts"]
                    row["last_message"] = ev["message"]
                    if ev["device_name"]:
                        row["device_name"] = ev["device_name"]
        return out
