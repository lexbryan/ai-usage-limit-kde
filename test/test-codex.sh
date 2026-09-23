#!/usr/bin/env bash
# Tests for package/contents/code/aiul-codex-read.py against synthetic rollout trees.
# AIUL_CODEX_SESSIONS points it at a fixture, so a real ~/.codex is never read.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
READ="$here/../package/contents/code/aiul-codex-read.py"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
no() { fail=$((fail+1)); echo "  FAIL $1: $2"; }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "got '$2', want '$3'"; }

NOW=$(date '+%s')
run() { AIUL_CODEX_SESSIONS="$1" python3 "$READ"; }
field() { python3 -c "
import json,sys
t=sys.stdin.read()
if not t.strip(): print('<empty>'); raise SystemExit
d=json.loads(t)
cur=d
for k in sys.argv[1].split('.'):
    cur = cur[int(k)] if k.isdigit() else cur[k]
print(cur)" "$2"; }

# record <file> <used> <window_minutes> <resets_at> [iso-timestamp]
record() {
  local ts=${5:-$(date -u -d "@$NOW" '+%Y-%m-%dT%H:%M:%S.000Z')}
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":%s,"window_minutes":%s,"resets_at":%s},"secondary":null,"plan_type":"pro"}}}\n' \
    "$ts" "$2" "$3" "$4" >> "$1"
}

echo "absent or empty:"
eq "no sessions directory at all" "$(run "$work/nothing" | field . x 2>/dev/null || echo '<empty>')" "<empty>"
mkdir -p "$work/empty/2026/09/09"
eq "directories but no rollouts" "$(run "$work/empty" | field . x 2>/dev/null || echo '<empty>')" "<empty>"
d="$work/norl/2026/09/09"; mkdir -p "$d"; echo '{"type":"other"}' > "$d/rollout-a.jsonl"
eq "rollouts with no rate_limits" "$(run "$work/norl" | field . x 2>/dev/null || echo '<empty>')" "<empty>"

echo "reading a window:"
d="$work/one/2026/09/09"; mkdir -p "$d"
record "$d/rollout-a.jsonl" 73.5 10080 $((NOW+400000))
out=$(run "$work/one")
eq "used_percentage" "$(printf '%s' "$out" | field . windows.0.used_percentage)" "73.5"
eq "weekly window labelled 7d" "$(printf '%s' "$out" | field . windows.0.label)" "7d"
eq "plan surfaced" "$(printf '%s' "$out" | field . plan)" "pro"
eq "provider tagged" "$(printf '%s' "$out" | field . provider)" "codex"

echo "labels come from window_minutes, not the slot name:"
for pair in "300 5h" "60 1h" "1440 1d" "10080 7d" "43200 30d" "90 90m"; do
  set -- $pair
  d="$work/lbl$1/2026/09/09"; mkdir -p "$d"
  record "$d/rollout-a.jsonl" 10 "$1" $((NOW+1000))
  eq "window_minutes=$1 -> $2" "$(run "$work/lbl$1" | field . windows.0.label)" "$2"
done

echo "picks the newest reading:"
d="$work/many/2026/09"; mkdir -p "$d/08" "$d/09"
record "$d/08/rollout-old.jsonl" 11 10080 $((NOW+1))
record "$d/09/rollout-new.jsonl" 88 10080 $((NOW+2))
touch -d '2 days ago' "$d/08/rollout-old.jsonl"
eq "newest day directory wins" "$(run "$work/many" | field . windows.0.used_percentage)" "88.0"

d="$work/samefile/2026/09/09"; mkdir -p "$d"
record "$d/rollout-a.jsonl" 20 10080 $((NOW+1))
record "$d/rollout-a.jsonl" 55 10080 $((NOW+2))
eq "last record in the file wins" "$(run "$work/samefile" | field . windows.0.used_percentage)" "55.0"

echo "only the tail is read:"
d="$work/big/2026/09/09"; mkdir -p "$d"
record "$d/rollout-a.jsonl" 1 10080 $((NOW+1))
python3 -c "
import sys
pad = '{\"type\":\"filler\",\"blob\":\"' + 'x'*4000 + '\"}\n'
open('$d/rollout-a.jsonl','a').write(pad * 400)"   # ~1.6 MB of noise
record "$d/rollout-a.jsonl" 42 10080 $((NOW+2))
sz=$(stat -c%s "$d/rollout-a.jsonl")
eq "fixture is genuinely large (>1MB)" "$([ "$sz" -gt 1000000 ] && echo yes || echo no)" "yes"
eq "still finds the trailing record" "$(run "$work/big" | field . windows.0.used_percentage)" "42.0"

echo "malformed input:"
d="$work/bad/2026/09/09"; mkdir -p "$d"
printf '{"payload":{"rate_limits":{"primary":{"used_pe\n' > "$d/rollout-a.jsonl"
record "$d/rollout-a.jsonl" 33 10080 $((NOW+1))
printf 'not json at all\n' >> "$d/rollout-a.jsonl"
eq "skips truncated and junk lines" "$(run "$work/bad" | field . windows.0.used_percentage)" "33.0"

d="$work/nonum/2026/09/09"; mkdir -p "$d"
printf '{"payload":{"rate_limits":{"primary":{"used_percent":"high","window_minutes":10080}}}}\n' > "$d/rollout-a.jsonl"
eq "non-numeric percentage ignored" "$(run "$work/nonum" | field . x 2>/dev/null || echo '<empty>')" "<empty>"

echo "clamping:"
d="$work/clamp/2026/09/09"; mkdir -p "$d"
record "$d/rollout-a.jsonl" 140 10080 $((NOW+1))
eq "over 100 clamps" "$(run "$work/clamp" | field . windows.0.used_percentage)" "100.0"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
