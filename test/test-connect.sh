#!/usr/bin/env bash
# Tests for what the widget's Connect / Disconnect run: connect.sh,
# claude-state.py and unwrap-statusline.py.
#
# Every case runs in a throwaway HOME, so a real ~/.claude is never touched.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
code="$here/../package/contents/code"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unset XDG_DATA_HOME AIUL_CACHE

pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
no() { fail=$((fail+1)); echo "  FAIL $1: $2"; }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "got '$2', want '$3'"; }

fresh() { rm -rf "$work/home"; mkdir -p "$work/home"; H="$work/home"; }
state() { HOME="$H" python3 "$code/claude-state.py"; }
connect() { HOME="$H" bash "$code/connect.sh" "$@"; }
unwrap() { HOME="$H" python3 "$code/unwrap-statusline.py" "$@"; }
cmdof() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("statusLine") or {}).get("command",""))' "$H/.claude/settings.json"; }
settings() { mkdir -p "$H/.claude"; printf '%s' "$1" > "$H/.claude/settings.json"; }

echo "state:"
fresh
eq "no ~/.claude is absent" "$(state)" "absent"
mkdir -p "$H/.claude"
eq "~/.claude without settings is unwired" "$(state)" "unwired"
settings '{"statusLine":{"type":"command","command":"bash /opt/mybar.sh"}}'
eq "someone else's statusline is unwired" "$(state)" "unwired"
settings '{not json'
eq "broken settings.json is unwired, not a crash" "$(state)" "unwired"
settings '{"statusLine":{"type":"command","command":"bash /x/aiul-statusline.sh bash /opt/mybar.sh"}}'
eq "wrapped is wired" "$(state)" "wired"
printf '#!/bin/bash\n# aiul_cache="$HOME/x"\necho hi\n' > "$H/pub.sh"
settings "{\"statusLine\":{\"type\":\"command\",\"command\":\"bash $H/pub.sh\"}}"
eq "an old in-place patch counts as wired" "$(state)" "wired"
[ -d "$code/__pycache__" ] && no "no bytecode left in the package" "found $code/__pycache__" \
    || ok "no bytecode left in the package"

echo "connect:"
fresh
printf '#!/bin/bash\ncat >/dev/null\necho MYBAR\n' > "$H/mybar.sh"
settings "{\"theme\":\"dark\",\"statusLine\":{\"type\":\"command\",\"command\":\"bash $H/mybar.sh\",\"padding\":0}}"
before=$(cat "$H/.claude/settings.json")
connect --dry-run >/dev/null
eq "dry run writes nothing" "$(cat "$H/.claude/settings.json")" "$before"
[ -e "$H/.local/share/ai-usage-limit" ] && no "dry run copies nothing" "publisher copied" \
    || ok "dry run copies nothing"

connect >/dev/null
wrapper="$H/.local/share/ai-usage-limit/aiul-statusline.sh"
[ -x "$wrapper" ] && ok "publisher copied out of the package" || no "publisher copied" "missing $wrapper"
eq "statusLine wraps the original" "$(cmdof)" "bash $wrapper bash $H/mybar.sh"
eq "state is now wired" "$(state)" "wired"
ls "$H/.claude/"settings.json.bak-aiul-* >/dev/null 2>&1 && ok "settings backed up" || no "backup" "none"
eq "other settings kept" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["theme"])' "$H/.claude/settings.json")" "dark"

first=$(cmdof)
out=$(connect)
eq "connecting twice changes nothing" "$(cmdof)" "$first"
case "$out" in *"left alone"*) ok "and says so" ;; *) no "second connect" "$out" ;; esac

# The point of all this: a statusline render through the configured command
# publishes the cache AND still shows the user's own statusline.
now=$(date '+%s')
payload="{\"model\":{\"display_name\":\"Opus 5\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":62,\"resets_at\":$((now+9420))},\"seven_day\":{\"used_percentage\":41,\"resets_at\":$((now+230000))}}}"
shown=$(printf '%s' "$payload" | HOME="$H" bash -c "$(cmdof)")
eq "your statusline still renders" "$shown" "MYBAR"
eq "the render published the cache" \
    "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["five_hour"]["used_percentage"])' "$H/.claude/cache/rate-limits.json" 2>/dev/null)" "62"

echo "connect with XDG_DATA_HOME:"
fresh; mkdir -p "$H/.claude"
HOME="$H" XDG_DATA_HOME="$H/data" bash "$code/connect.sh" >/dev/null
[ -f "$H/data/ai-usage-limit/aiul-statusline.sh" ] && ok "publisher follows XDG_DATA_HOME" \
    || no "XDG_DATA_HOME" "not under $H/data"
eq "no statusline before: wrapper stands alone" "$(cmdof)" "bash $H/data/ai-usage-limit/aiul-statusline.sh"

echo "unwrap:"
fresh
settings '{"statusLine":{"type":"command","command":"bash /x/aiul-statusline.sh bash /opt/mybar.sh --flag","padding":0}}'
unwrap >/dev/null
eq "original command restored" "$(cmdof)" "bash /opt/mybar.sh --flag"
eq "state back to unwired" "$(state)" "unwired"
ls "$H/.claude/"settings.json.bak-aiul-* >/dev/null 2>&1 && ok "settings backed up" || no "backup" "none"

settings '{"statusLine":{"type":"command","command":"bash /x/aiul-statusline.sh"}}'
unwrap >/dev/null
eq "a lone wrapper is removed" "$(python3 -c 'import json,sys; print("statusLine" in json.load(open(sys.argv[1])))' "$H/.claude/settings.json")" "False"

settings '{"statusLine":{"type":"command","command":"bash /opt/mybar.sh"}}'
before=$(cat "$H/.claude/settings.json")
unwrap >/dev/null
eq "someone else's statusline is left alone" "$(cat "$H/.claude/settings.json")" "$before"

settings '{not json'
unwrap >/dev/null 2>&1
[ "$?" -ne 0 ] && ok "non-zero exit on invalid JSON" || no "invalid JSON" "exited 0"
eq "and the file is untouched" "$(cat "$H/.claude/settings.json")" "{not json"

fresh
unwrap >/dev/null
[ "$?" -eq 0 ] && ok "no settings.json is fine" || no "no settings.json" "non-zero"

echo "round trip:"
fresh
settings '{"statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh","padding":0}}'
before=$(cmdof)
connect >/dev/null && unwrap >/dev/null
eq "connect then disconnect gives back the exact command" "$(cmdof)" "$before"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
