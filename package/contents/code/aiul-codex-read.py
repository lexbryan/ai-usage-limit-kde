#!/usr/bin/env python3
"""Print Codex's latest rate-limit reading as normalised JSON, or nothing.

Unlike Claude Code, Codex writes its rate limits to disk on its own: every
`token_count` event in a session rollout carries a `rate_limits` block. So there
is nothing to hook — the numbers are already there to be read.

What has to be handled carefully is cost. A rollout tree is large (hundreds of
files, tens of MB each is possible), and this runs on a timer, so it must never
read the whole tree:

  * sessions live in sessions/YYYY/MM/DD/, so the newest file is found by walking
    the dated directories newest-first and stat-ing only the few most recent days
  * only the TAIL of that one file is read, and scanned backwards for the last
    usable record

Output schema, provider-agnostic so a second provider can reuse it:

    {"updated_at": 1786841654, "provider": "codex", "plan": "pro",
     "windows": [{"label": "7d", "window_minutes": 10080,
                  "used_percentage": 0.0, "resets_at": 1786841654}]}

Prints nothing and exits 0 when there is no reading — an absent provider is a
normal state, not an error.
"""
import io
import json
import os
import sys
import time

SESSIONS = os.path.expanduser("~/.codex/sessions")
TAIL_BYTES = 512 * 1024      # enough for many records; we want the last one
DAY_DIRS_TO_CHECK = 6        # newest few days, in case the latest is empty


def newest_rollout(root):
    """Newest rollout-*.jsonl, found without stat-ing the whole tree."""
    if not os.path.isdir(root):
        return None

    def subdirs(path):
        try:
            return sorted((e.name for e in os.scandir(path) if e.is_dir()),
                          reverse=True)
        except OSError:
            return []

    days = []
    for year in subdirs(root):
        for month in subdirs(os.path.join(root, year)):
            for day in subdirs(os.path.join(root, year, month)):
                days.append(os.path.join(root, year, month, day))
                if len(days) >= DAY_DIRS_TO_CHECK:
                    break
            if len(days) >= DAY_DIRS_TO_CHECK:
                break
        if len(days) >= DAY_DIRS_TO_CHECK:
            break

    best, best_mtime = None, -1.0
    for day in days:
        try:
            entries = list(os.scandir(day))
        except OSError:
            continue
        for e in entries:
            if not e.name.startswith("rollout-") or not e.name.endswith(".jsonl"):
                continue
            try:
                m = e.stat().st_mtime
            except OSError:
                continue
            if m > best_mtime:
                best, best_mtime = e.path, m
    return best


def last_rate_limits(path):
    """Scan the tail of one rollout backwards for the newest rate_limits block."""
    try:
        size = os.path.getsize(path)
        with io.open(path, "rb") as fh:
            if size > TAIL_BYTES:
                fh.seek(size - TAIL_BYTES)
                fh.readline()          # discard the partial line at the seam
            chunk = fh.read()
    except OSError:
        return None, None

    text = chunk.decode("utf-8", errors="replace")
    for line in reversed(text.splitlines()):
        if '"rate_limits"' not in line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue                    # truncated or interleaved line
        payload = rec.get("payload")
        if not isinstance(payload, dict):
            continue
        rl = payload.get("rate_limits")
        if isinstance(rl, dict):
            return rl, rec.get("timestamp")
    return None, None


def label_for(window_minutes):
    """Name a window from its own length — never from which slot it arrived in.

    Codex reports `primary` and `secondary`, but which duration lands in which
    slot is not fixed (on a Pro plan the only window seen is a weekly one, and it
    arrives as `primary`). Naming from window_minutes keeps the label honest.
    """
    if not isinstance(window_minutes, (int, float)) or window_minutes <= 0:
        return None
    minutes = int(window_minutes)
    if minutes % (60 * 24) == 0:
        return "%dd" % (minutes // (60 * 24))
    if minutes % 60 == 0:
        return "%dh" % (minutes // 60)
    return "%dm" % minutes


def parse_iso(ts):
    if not isinstance(ts, str):
        return None
    try:
        cleaned = ts.replace("Z", "+00:00")
        from datetime import datetime
        return int(datetime.fromisoformat(cleaned).timestamp())
    except Exception:
        return None


def main():
    root = os.environ.get("AIUL_CODEX_SESSIONS", SESSIONS)
    path = newest_rollout(root)
    if not path:
        return 0

    rl, ts = last_rate_limits(path)
    if not rl:
        return 0

    windows = []
    for slot in ("primary", "secondary"):
        w = rl.get(slot)
        if not isinstance(w, dict):
            continue
        used = w.get("used_percent")
        if not isinstance(used, (int, float)):
            continue
        label = label_for(w.get("window_minutes"))
        windows.append({
            "label": label or slot,
            "window_minutes": w.get("window_minutes"),
            "used_percentage": max(0.0, min(100.0, float(used))),
            "resets_at": w.get("resets_at")
                if isinstance(w.get("resets_at"), (int, float)) else None,
        })
    if not windows:
        return 0

    updated = parse_iso(ts)
    if updated is None:
        try:
            updated = int(os.path.getmtime(path))
        except OSError:
            updated = int(time.time())

    plan = rl.get("plan_type")
    json.dump({
        "updated_at": updated,
        "provider": "codex",
        "plan": plan if isinstance(plan, str) else None,
        "windows": windows,
    }, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
