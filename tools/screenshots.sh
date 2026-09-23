#!/usr/bin/env bash
# Render the widget headlessly and screenshot it: the popup, and the panel view
# both horizontal and vertical. The images are the ones the README and the KDE
# Store listing use, and the run doubles as the render smoke test — any QML
# warning or error fails it, which the node tests alone can't catch.
#
# Everything happens in a throwaway HOME, inside a nested virtual KWin on a
# private D-Bus, so your own session, panels and ~/.claude are never touched.
#
# Needs a Plasma 6 machine: kwin_wayland, plasmawindowed, spectacle,
# kpackagetool6, dbus-run-session. ImageMagick, if present, trims the shots.
#
#   tools/screenshots.sh [out-dir]        default: docs/
set -uo pipefail

# --- inside the private bus: one window, one shot -----------------------------
if [ "${1:-}" = --inside ]; then
    home=$2 id=$3 png=$4
    sock="aiul-shot-$$"
    kwin_wayland --virtual --width 900 --height 650 --no-lockscreen \
        --socket "$sock" >/dev/null 2>&1 &
    kw=$!
    for _ in $(seq 50); do
        [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$sock" ] && break
        sleep 0.2
    done
    QT_FORCE_STDERR_LOGGING=1 HOME="$home" WAYLAND_DISPLAY="$sock" QT_QPA_PLATFORM=wayland \
        plasmawindowed "$id" >"$png.log" 2>&1 &
    pw=$!
    sleep 5   # load, first poll of every command, first render
    WAYLAND_DISPLAY="$sock" QT_QPA_PLATFORM=wayland spectacle -b -n -a -e -S -o "$png" >/dev/null 2>&1
    kill "$pw" "$kw" 2>/dev/null
    wait 2>/dev/null
    exit 0
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:-$root/docs}
ID="me.lexbryan.aiusagelimit"

for tool in kwin_wayland plasmawindowed spectacle kpackagetool6 dbus-run-session; do
    command -v "$tool" >/dev/null 2>&1 || { echo "needs $tool (run this on Plasma 6)"; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

# --- fixtures: a fresh Claude reading, and Codex running low -----------------
home="$work/home"
now=$(date '+%s')
mkdir -p "$home/.claude/cache" "$home/.codex/sessions/2026/01/01"
printf '{"updated_at":%s,"model":"Opus 5.5","five_hour":{"used_percentage":62,"resets_at":%s},"seven_day":{"used_percentage":41,"resets_at":%s}}\n' \
    "$((now - 180))" "$((now + 9420))" "$((now + 230000))" > "$home/.claude/cache/rate-limits.json"
printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":87,"window_minutes":10080,"resets_at":%s},"secondary":null,"plan_type":"pro"}}}\n' \
    "$(date -u -d "@$((now - 180))" '+%Y-%m-%dT%H:%M:%S.000Z')" "$((now + 300000))" \
    > "$home/.codex/sessions/2026/01/01/rollout-fixture.jsonl"
echo '{"statusLine":{"type":"command","command":"bash /x/aiul-statusline.sh"}}' \
    > "$home/.claude/settings.json"

# --- the widget, plus test-only copies that put the panel view in the window --
install_pkg() { HOME="$home" kpackagetool6 --type Plasma/Applet --install "$1" >/dev/null; }
install_pkg "$root/package"
for layout in horizontal vertical; do
    cp -r "$root/package" "$work/$layout"
    sed -i "s/\"$ID\"/\"$ID.$layout\"/" "$work/$layout/metadata.json"
    sed -i 's/fullRepresentation: FullRepresentation {/fullRepresentation: CompactRepresentation {/' \
        "$work/$layout/contents/ui/main.qml"
    [ "$layout" = vertical ] && sed -i 's/readonly property bool vertical: .*/readonly property bool vertical: true/' \
        "$work/$layout/contents/ui/CompactRepresentation.qml"
    install_pkg "$work/$layout"
done

# --- shoot --------------------------------------------------------------------
rc=0
for shot in "popup:$ID" "panel:$ID.horizontal" "panel-vertical:$ID.vertical"; do
    name=${shot%%:*} id=${shot#*:}
    png="$work/$name.png"
    dbus-run-session -- "$0" --inside "$home" "$id" "$png" >/dev/null 2>&1
    if [ ! -s "$png" ]; then
        echo "FAIL $name: no screenshot taken"; rc=1; continue
    fi
    # Only our own files: the private bus has no portal, and Qt says so.
    problems=$(grep -E '\.qml:|\.mjs:|qt\.qml' "$png.log")
    if [ -n "$problems" ]; then
        echo "FAIL $name: QML reported problems"; echo "$problems" | sed 's/^/    /'; rc=1
    fi
    # The window is captured without decoration or shadow; trim the empty
    # space plasmawindowed leaves around the content, keep a little margin.
    if command -v magick >/dev/null 2>&1; then
        bg=$(magick "$png" -format '%[pixel:p{1,1}]' info:)
        magick "$png" -bordercolor "$bg" -border 1 -fuzz 4% -trim +repage \
            -bordercolor "$bg" -border 16 "$png"
    fi
    cp "$png" "$out/$name.png"
    echo "ok   $name -> $out/$name.png"
done
exit "$rc"
