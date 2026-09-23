#!/usr/bin/env bash
# Remove everything install.sh (or the widget's Connect button) put in place.
#
# The statusLine is unwrapped rather than cleared: your original command is put
# back exactly as it was, so a statusline you had before this is untouched.
set -uo pipefail

ID="me.lexbryan.aiusagelimit"
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dest="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$ID"
libdir="${XDG_DATA_HOME:-$HOME/.local/share}/ai-usage-limit"

# Unwrap first: this uses the checkout's copy, which is still here after the
# installed widget is gone.
python3 "$here/package/contents/code/unwrap-statusline.py"

if [ -L "$dest" ]; then
    rm -f "$dest" && echo "removed link $dest"
elif [ -d "$dest" ]; then
    kpackagetool6 --type Plasma/Applet --remove "$ID" >/dev/null 2>&1 \
        || rm -rf "$dest"
    echo "removed $dest"
fi

# Only the publisher: the GNOME version keeps its own files in this directory,
# and they stay if it is installed too.
if [ -f "$libdir/aiul-statusline.sh" ]; then
    rm -f "$libdir/aiul-statusline.sh" && echo "removed $libdir/aiul-statusline.sh"
    rmdir "$libdir" 2>/dev/null && echo "removed $libdir"
fi

echo
echo "The cache at ~/.claude/cache/rate-limits.json is left in place; delete it if you like."
echo "If the widget is still on a panel, right-click it → Remove."
