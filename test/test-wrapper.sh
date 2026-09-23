#!/usr/bin/env bash
# Tests for package/contents/code/aiul-statusline.sh — the publish-and-forward wrapper.
# Uses AIUL_CACHE to write into a temp dir, so a live cache is never touched.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WRAP="$here/../package/contents/code/aiul-statusline.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export AIUL_CACHE="$work/rate-limits.json"

pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
no() { fail=$((fail+1)); echo "  FAIL $1: $2"; }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "got '$2', want '$3'"; }

NOW=$(date '+%s')
payload() {
  printf '{"session_id":"s1","model":{"display_name":"Opus 5"},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}' \
    "${1:-62}" "$((NOW+9420))" "${2:-41}" "$((NOW+230000))"
}

echo "forwarding:"
out=$(payload | "$WRAP" cat)
eq "stdin reaches the wrapped command" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["session_id"])')" "s1"

out=$(payload | "$WRAP" bash -c 'cat >/dev/null; echo MY-STATUSLINE')
eq "wrapped stdout passes through" "$out" "MY-STATUSLINE"

payload | "$WRAP" bash -c 'cat >/dev/null; exit 7' >/dev/null 2>&1
eq "wrapped exit status passes through" "$?" "7"

echo "publishing:"
rm -f "$AIUL_CACHE"; payload 62 41 | "$WRAP" cat >/dev/null
[ -f "$AIUL_CACHE" ] && ok "cache written" || no "cache written" "no file"
eq "five_hour recorded" \
   "$(python3 -c 'import json;print(json.load(open("'"$AIUL_CACHE"'"))["five_hour"]["used_percentage"])')" "62"
eq "model recorded" \
   "$(python3 -c 'import json;print(json.load(open("'"$AIUL_CACHE"'"))["model"])')" "Opus 5"
eq "no stray temp files" "$(find "$work" -name 'rate-limits.json.*' | wc -l)" "0"

echo "python3 fallback (jq hidden):"
rm -f "$AIUL_CACHE"
fakebin="$work/fakebin"; mkdir -p "$fakebin"
for c in bash cat date mkdir mv rm dirname python3 find; do
  src=$(command -v "$c") && ln -sf "$src" "$fakebin/$c"
done
payload 30 20 | env PATH="$fakebin" "$WRAP" cat >/dev/null
[ -f "$AIUL_CACHE" ] && ok "published without jq" || no "published without jq" "no file"
eq "fallback value correct" \
   "$(python3 -c 'import json;print(json.load(open("'"$AIUL_CACHE"'"))["five_hour"]["used_percentage"])')" "30"

echo "degraded input:"
rm -f "$AIUL_CACHE"
out=$(printf 'not json at all' | "$WRAP" bash -c 'cat >/dev/null; echo STILL-RAN')
eq "garbage in: wrapped command still runs" "$out" "STILL-RAN"
[ -f "$AIUL_CACHE" ] && no "garbage in: no cache written" "file was created" || ok "garbage in: no cache written"

rm -f "$AIUL_CACHE"
out=$(printf '{"session_id":"s1"}' | "$WRAP" bash -c 'cat >/dev/null; echo STILL-RAN')
eq "no rate_limits: wrapped command still runs" "$out" "STILL-RAN"
[ -f "$AIUL_CACHE" ] && no "no rate_limits: nothing written" "file was created" || ok "no rate_limits: nothing written"

echo "standalone (no wrapped command):"
out=$(payload 62 41 | "$WRAP")
case "$out" in
  *"5h "*"38%"*"7d "*"59%"*) ok "renders its own remaining-capacity line" ;;
  *) no "renders its own line" "got '$out'" ;;
esac
case "$out" in *"Opus 5"*) ok "names the model" ;; *) no "names the model" "got '$out'" ;; esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
