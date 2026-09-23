#!/usr/bin/env bash
# Install the widget from this checkout and connect Claude Code's statusLine.
#
# This is the from-source route. Most people should get the widget from the KDE
# Store instead (right-click the panel → Add or Manage Widgets → Get New Widgets)
# and press "Connect Claude Code" in its popup, which does step 2 below.
#
#   1. the widget     -> ~/.local/share/plasma/plasmoids/<id>
#   2. the publisher  -> ~/.local/share/ai-usage-limit/aiul-statusline.sh,
#                        wrapped around whatever statusLine you already had
#
# Everything here is idempotent; re-running is safe.
#
#   --link     symlink the widget to this checkout instead of copying it, so
#              edits here take effect on the next plasmashell restart
#   --dry-run  say what would change, change nothing
set -uo pipefail

ID="me.lexbryan.aiusagelimit"
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dest="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$ID"

link=no
dry=no
for arg in "$@"; do
    case "$arg" in
        --link) link=yes ;;
        --dry-run) dry=yes ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say() { printf '%s\n' "$*"; }
run() { if [ "$dry" = yes ]; then say "  would: $*"; else "$@"; fi; }

# --- 0. dependencies ----------------------------------------------------------
if ! command -v kpackagetool6 >/dev/null 2>&1; then
    say "kpackagetool6 not found. This widget needs KDE Plasma 6."
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    say "missing: python3"
    say "  Debian/Ubuntu:  sudo apt-get install -y python3"
    say "  Fedora:         sudo dnf install -y python3"
    say "  Arch:           sudo pacman -S python"
    exit 1
fi
command -v jq >/dev/null 2>&1 || \
    say "note: jq not found — the publisher will use python3 instead (slightly slower, works fine)."

ver=$(plasmashell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
if [ -n "$ver" ] && [ "$ver" -lt 6 ]; then
    say "Plasma $ver is older than this widget supports (6.0+)."
    exit 1
fi

# --- 1. the widget ------------------------------------------------------------
if [ "$link" = yes ]; then
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        run rm -rf "$dest"
    fi
    run mkdir -p "$(dirname "$dest")"
    run ln -sfn "$here/package" "$dest"
    say "widget linked      $dest -> $here/package"
else
    # A dev symlink would be followed by an upgrade and written through into
    # this checkout, so replace it outright.
    if [ -L "$dest" ]; then
        run rm -f "$dest"
    fi
    if [ -d "$dest" ]; then
        run kpackagetool6 --type Plasma/Applet --upgrade "$here/package" >/dev/null
        say "widget upgraded in $dest"
    else
        run kpackagetool6 --type Plasma/Applet --install "$here/package" >/dev/null
        say "widget installed to $dest"
    fi
fi

# --- 2. the publisher ---------------------------------------------------------
if [ "$dry" = yes ]; then
    bash "$here/package/contents/code/connect.sh" --dry-run
else
    bash "$here/package/contents/code/connect.sh" || {
        say "could not configure statusLine automatically. Use the widget's"
        say "\"Connect Claude Code\" button, or see the README."
    }
fi

if [ -d "$HOME/.codex/sessions" ]; then
    say "codex: sessions found, readings will show up by themselves"
else
    say "codex: no ~/.codex/sessions yet, so it stays quiet until you run Codex"
fi

say ""
say "Add it to a panel: right-click the panel → Add or Manage Widgets…,"
say "search for \"AI Usage Limit\" and drag it onto the panel."
say ""
say "Already on a panel from an earlier install? Plasma keeps the old code"
say "loaded until it restarts:  systemctl --user restart plasma-plasmashell"
say ""
say "The widget reads '⚡ –' until a Claude Code session draws its statusline"
say "once. That is the first moment the numbers exist anywhere."
