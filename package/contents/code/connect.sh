#!/usr/bin/env bash
# Point Claude Code's statusLine at the publisher. Run by the widget's
# "Connect Claude Code" button and by install.sh.
#
# A widget installed from the KDE Store gets no install hook, so this step can't
# happen at install time — the widget offers it instead, once, on first run.
#
# The wrapper is copied OUT of the widget package before statusLine is pointed
# at it. The package directory is replaced on every store update and removed
# with the widget, and statusLine must never name a file that has gone away:
# Claude Code would lose your statusline entirely. The copy lives where the
# GNOME version keeps it, so the two share one publisher.
#
# Idempotent: an already-wrapped statusLine is left alone.
#
#   connect.sh [--dry-run] [--settings PATH]
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
libdir="${XDG_DATA_HOME:-$HOME/.local/share}/ai-usage-limit"
wrapper="$libdir/aiul-statusline.sh"

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to edit ~/.claude/settings.json" >&2
    exit 1
fi

for arg in "$@"; do
    if [ "$arg" = --dry-run ]; then
        # Nothing is copied on a dry run, so validate against the packaged copy.
        exec python3 "$here/configure-statusline.py" "$here/aiul-statusline.sh" "$@"
    fi
done

mkdir -p "$libdir" && cp "$here/aiul-statusline.sh" "$wrapper" && chmod +x "$wrapper" || {
    echo "could not install the publisher to $wrapper" >&2
    exit 1
}
exec python3 "$here/configure-statusline.py" "$wrapper" "$@"
