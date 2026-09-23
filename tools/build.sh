#!/usr/bin/env bash
# Build the .plasmoid that goes to the KDE Store and to GitHub releases.
#
# A .plasmoid is a zip of package/ with metadata.json at its root. Plasma's
# "Get New Widgets" and "Install Widget From Local File…" both take it as is,
# and so does `kpackagetool6 --type Plasma/Applet --install <file>`.
#
# Prints the path of what it built.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Version"])' \
    "$root/package/metadata.json")
out="$root/dist/ai-usage-limit-$version.plasmoid"

mkdir -p "$root/dist"
rm -f "$out"
(cd "$root/package" && zip -qr -X "$out" . -x '*/__pycache__/*' '*.pyc')
echo "$out"
