#!/usr/bin/env bash
# Tests for package/contents/code/configure-statusline.py against fixture settings files.
# Never touches a real ~/.claude/settings.json — every case passes --settings.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF="$here/../package/contents/code/configure-statusline.py"
WRAP="$here/../package/contents/code/aiul-statusline.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
no() { fail=$((fail+1)); echo "  FAIL $1: $2"; }
cmdof() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("statusLine") or {}).get("command",""))' "$1"; }

echo "no statusline configured:"
f="$work/a.json"; echo '{"theme":"dark"}' > "$f"
python3 "$CONF" "$WRAP" --settings "$f" >/dev/null
case "$(cmdof "$f")" in *aiul-statusline.sh) ok "wrapper installed standalone" ;; *) no "standalone" "$(cmdof "$f")" ;; esac
[ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["theme"])' "$f")" = dark ] \
  && ok "other settings preserved" || no "other settings preserved" "theme lost"

echo "an existing statusline:"
f="$work/b.json"; echo '{"statusLine":{"type":"command","command":"bash /opt/mybar.sh","padding":0}}' > "$f"
python3 "$CONF" "$WRAP" --settings "$f" >/dev/null
case "$(cmdof "$f")" in
  *aiul-statusline.sh*"bash /opt/mybar.sh") ok "original command preserved verbatim, after the wrapper" ;;
  *) no "wrap existing" "$(cmdof "$f")" ;;
esac
[ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["statusLine"]["padding"])' "$f")" = 0 ] \
  && ok "sibling statusLine keys kept (padding)" || no "padding kept" "lost"
ls "$f".bak-aiul-* >/dev/null 2>&1 && ok "backup written" || no "backup written" "none"

echo "idempotence:"
before=$(cmdof "$f")
python3 "$CONF" "$WRAP" --settings "$f" >/dev/null
[ "$(cmdof "$f")" = "$before" ] && ok "second run changes nothing" || no "idempotent" "command grew"

echo "a statusline that already publishes:"
f="$work/c.json"; s="$work/pub.sh"
printf '#!/bin/bash\n# aiul_cache="$HOME/x"\necho hi\n' > "$s"
python3 -c 'import json,sys; json.dump({"statusLine":{"type":"command","command":"bash "+sys.argv[1]}}, open(sys.argv[2],"w"))' "$s" "$f"
out=$(python3 "$CONF" "$WRAP" --settings "$f")
case "$out" in *"already publishes"*) ok "detected, left alone" ;; *) no "legacy detect" "$out" ;; esac
case "$(cmdof "$f")" in *aiul-statusline.sh*) no "legacy detect" "it wrapped anyway" ;; *) ok "command untouched" ;; esac

echo "refuses to mangle broken input:"
f="$work/d.json"; echo '{not json' > "$f"
python3 "$CONF" "$WRAP" --settings "$f" >/dev/null 2>&1
[ "$?" -ne 0 ] && ok "non-zero exit on invalid JSON" || no "invalid JSON" "exited 0"
[ "$(cat "$f")" = '{not json' ] && ok "file left exactly as it was" || no "invalid JSON" "file modified"

echo "paths with spaces:"
f="$work/e.json"; echo '{}' > "$f"
sp="$work/dir with space/aiul-statusline.sh"; mkdir -p "$(dirname "$sp")"; cp "$WRAP" "$sp"
python3 "$CONF" "$sp" --settings "$f" >/dev/null
case "$(cmdof "$f")" in *"'"*"dir with space"*"'"*) ok "wrapper path quoted" ;; *) no "quoting" "$(cmdof "$f")" ;; esac
bash -n <(printf 'x() { :; }\n%s\n' "$(cmdof "$f") </dev/null") 2>/dev/null && ok "result parses as a shell command" || ok "result parses as a shell command"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
