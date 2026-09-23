#!/usr/bin/env python3
"""Undo connect.sh: put Claude Code's statusLine back exactly as it was.

    "bash /path/aiul-statusline.sh <original...>"  ->  "<original...>"

A statusLine that was only ever the wrapper is removed. Anything that doesn't
go through the wrapper is left alone. settings.json is backed up first.

Used by the widget's "Disconnect Claude Code" action and by uninstall.sh.

Usage: unwrap-statusline.py [--settings PATH]
"""
import io
import json
import os
import shutil
import sys
import time

MARKER = "aiul-statusline.sh"


def main(argv):
    settings = os.path.expanduser("~/.claude/settings.json")
    if len(argv) == 3 and argv[1] == "--settings":
        settings = os.path.expanduser(argv[2])
    elif len(argv) != 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    if not os.path.exists(settings):
        print("no settings.json — nothing to unwrap")
        return 0
    try:
        data = json.load(io.open(settings, encoding="utf-8"))
    except ValueError:
        print("settings.json is not valid JSON — left alone", file=sys.stderr)
        return 1
    line = data.get("statusLine") if isinstance(data, dict) else None
    cmd = line.get("command", "") if isinstance(line, dict) else ""
    if not isinstance(cmd, str) or MARKER not in cmd:
        print("statusLine does not go through the wrapper — left alone")
        return 0

    # "bash /path/aiul-statusline.sh <original...>" -> "<original...>"
    parts = cmd.split()
    original = ""
    for i, tok in enumerate(parts):
        if tok.endswith(MARKER) or tok.endswith(MARKER + "'"):
            original = " ".join(parts[i + 1:])
            break

    backup = "%s.bak-aiul-%s" % (settings, time.strftime("%Y%m%d-%H%M%S"))
    shutil.copy2(settings, backup)
    if original:
        line["command"] = original
        print("statusLine restored to: %s" % original)
    else:
        data.pop("statusLine", None)
        print("statusLine removed (there was nothing wrapped)")

    tmp = settings + ".tmp-aiul"
    with io.open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, settings)
    print("  backed up to %s" % backup)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
