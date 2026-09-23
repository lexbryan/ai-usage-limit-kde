#!/usr/bin/env bash
# Publish Claude Code's rate limits for the top-bar indicator, then hand the
# statusline payload on to whatever statusline you already had.
#
# Claude Code gives these numbers to the statusLine command and to nothing else,
# so something in that position has to write them down. Rather than patch your
# statusline script — which means finding a place to graft onto in a file this
# project didn't write — this wraps it:
#
#   statusLine.command = aiul-statusline.sh <your original command...>
#
# stdin is read once, the cache is published, and the same bytes are piped to
# your command untouched. Its stdout and exit status pass straight through, so
# from Claude Code's side nothing has changed.
#
# With no command given it prints a compact line of its own, so installing this
# on a machine with no statusline still leaves something readable in the bar.
#
# Nothing here is allowed to break your status line: every failure path falls
# through to running your command anyway.

set -uo pipefail

CACHE="${AIUL_CACHE:-$HOME/.claude/cache/rate-limits.json}"

input=$(cat)

# --- publish -----------------------------------------------------------------
# jq if it's here (your statusline probably already needs it), else python3,
# which Ubuntu and friends ship in the base system. If neither exists we simply
# skip publishing rather than failing.
publish() {
    [ -n "$input" ] || return 0
    mkdir -p "$(dirname "$CACHE")" 2>/dev/null || return 0
    local tmp="${CACHE}.$$"
    local now
    now=$(date '+%s')

    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$input" | jq -c --argjson now "$now" '
            select(.rate_limits != null) | {
                updated_at: $now,
                model: (.model.display_name // null),
                session_id: (.session_id // null),
                five_hour: (.rate_limits.five_hour // null),
                seven_day: (.rate_limits.seven_day // null)
            }' > "$tmp" 2>/dev/null
    elif command -v python3 >/dev/null 2>&1; then
        printf '%s' "$input" | python3 -c '
import json, sys, time
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
rl = d.get("rate_limits")
if not isinstance(rl, dict):
    sys.exit(1)
json.dump({
    "updated_at": int(time.time()),
    "model": (d.get("model") or {}).get("display_name"),
    "session_id": d.get("session_id"),
    "five_hour": rl.get("five_hour"),
    "seven_day": rl.get("seven_day"),
}, sys.stdout)
' > "$tmp" 2>/dev/null
    else
        return 0
    fi

    if [ -s "$tmp" ]; then
        mv -f "$tmp" "$CACHE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    else
        rm -f "$tmp" 2>/dev/null
    fi
    return 0
}

publish || true

# --- hand off ----------------------------------------------------------------
if [ "$#" -gt 0 ]; then
    printf '%s' "$input" | "$@"
    exit $?
fi

# No wrapped command: render a small line ourselves so the bar isn't empty.
# Remaining capacity, to match the indicator.
if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
bits = []
model = (d.get("model") or {}).get("display_name")
if model:
    bits.append(model)
rl = d.get("rate_limits") or {}
for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
    w = rl.get(key)
    if isinstance(w, dict) and isinstance(w.get("used_percentage"), (int, float)):
        left = max(0.0, min(100.0, 100.0 - w["used_percentage"]))
        segs = 5
        filled = max(0, min(segs, round(left * segs / 100.0)))
        bar = "▰" * filled + "▱" * (segs - filled)
        bits.append("%s %s %d%%" % (label, bar, round(left)))
sys.stdout.write(" | ".join(bits))
'
fi
