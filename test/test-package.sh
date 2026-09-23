#!/usr/bin/env bash
# The package as Plasma and the KDE Store will see it: metadata, every file the
# QML reaches for, the built .plasmoid, and — where kpackagetool6 exists — a
# full install.sh / uninstall.sh round trip in a throwaway HOME.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root="$here/.."
pkg="$root/package"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
no() { fail=$((fail+1)); echo "  FAIL $1: $2"; }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "got '$2', want '$3'"; }
meta() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))
cur=d
for k in sys.argv[2].split("."): cur=cur[k]
print(cur)' "$pkg/metadata.json" "$1" 2>/dev/null; }

echo "metadata:"
eq "applet package" "$(meta KPackageStructure)" "Plasma/Applet"
eq "id" "$(meta KPlugin.Id)" "me.lexbryan.aiusagelimit"
eq "plasma 6 api" "$(meta X-Plasma-API-Minimum-Version)" "6.0"
[[ "$(meta KPlugin.Version)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && ok "version is x.y.z" \
    || no "version" "$(meta KPlugin.Version)"
eq "install.sh uses the same id" "$(grep -oP '^ID="\K[^"]+' "$root/install.sh")" "$(meta KPlugin.Id)"
eq "uninstall.sh uses the same id" "$(grep -oP '^ID="\K[^"]+' "$root/uninstall.sh")" "$(meta KPlugin.Id)"

echo "everything the QML reaches for exists:"
missing=""
for f in $(grep -ohP 'codePath\("\K[^"]+' "$pkg/contents/ui/"*.qml); do
    [ -f "$pkg/contents/code/$f" ] || missing="$missing code/$f"
done
for f in claude codex; do
    [ -f "$pkg/contents/images/$f.png" ] || missing="$missing images/$f.png"
done
for f in $(grep -ohP '^\s+\K[A-Z][A-Za-z]+(?= \{)' "$pkg/contents/ui/"*.qml | sort -u); do
    # Our own components are the ones with a file; the rest come from imports.
    case "$f" in CompactRepresentation|FullRepresentation|ProviderChip|ProviderSection|SegmentBar|WindowRow)
        [ -f "$pkg/contents/ui/$f.qml" ] || missing="$missing ui/$f.qml" ;;
    esac
done
eq "no missing files" "${missing:-none}" "none"

echo "the .plasmoid:"
built=$("$root/tools/build.sh")
[ -f "$built" ] && ok "built $(basename "$built")" || no "build" "no output"
list=$(python3 -c 'import sys,zipfile; print("\n".join(zipfile.ZipFile(sys.argv[1]).namelist()))' "$built")
for f in metadata.json contents/ui/main.qml contents/code/logic.mjs contents/code/connect.sh \
         contents/code/aiul-statusline.sh contents/images/claude.png; do
    grep -qx "$f" <<<"$list" && ok "has $f" || no "zip contents" "no $f"
done
grep -q __pycache__ <<<"$list" && no "zip contents" "bytecode shipped" || ok "no bytecode shipped"

echo "install / uninstall round trip:"
if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "  skip (no kpackagetool6 here)"
else
    H="$work/home"; mkdir -p "$H/.claude"
    echo '{"statusLine":{"type":"command","command":"bash /opt/mybar.sh","padding":0}}' > "$H/.claude/settings.json"
    dest="$H/.local/share/plasma/plasmoids/me.lexbryan.aiusagelimit"
    env -u XDG_DATA_HOME HOME="$H" "$root/install.sh" >/dev/null 2>&1
    [ -f "$dest/metadata.json" ] && ok "widget installed" || no "install" "no $dest"
    grep -q aiul-statusline.sh "$H/.claude/settings.json" && ok "statusLine connected" || no "install" "not wrapped"
    env -u XDG_DATA_HOME HOME="$H" "$root/install.sh" >/dev/null 2>&1
    [ "$?" -eq 0 ] && ok "re-install upgrades cleanly" || no "re-install" "non-zero"
    env -u XDG_DATA_HOME HOME="$H" "$root/uninstall.sh" >/dev/null 2>&1
    [ -e "$dest" ] && no "uninstall" "$dest still there" || ok "widget removed"
    eq "statusLine restored" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["statusLine"]["command"])' "$H/.claude/settings.json")" "bash /opt/mybar.sh"
    [ -e "$H/.local/share/ai-usage-limit" ] && no "uninstall" "publisher left behind" || ok "publisher removed"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
