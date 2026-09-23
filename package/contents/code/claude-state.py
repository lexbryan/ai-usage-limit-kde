#!/usr/bin/env python3
"""Print whether Claude Code is set up to publish rate limits for the widget.

One word on stdout:

  wired     statusLine goes through aiul-statusline.sh, or an older in-place
            patch already publishes the cache itself
  unwired   Claude Code is here but its statusLine doesn't publish
  absent    no ~/.claude at all — Claude Code isn't installed, so the widget
            shouldn't offer to connect it

Usage: claude-state.py [--settings PATH]
"""
import importlib.util
import io
import json
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))

# Reuse the configurator's own markers and legacy detection, so "wired" here
# means exactly what "left alone" means there. Importing it must not leave a
# __pycache__ behind in the installed widget.
sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location(
    "configure_statusline", os.path.join(here, "configure-statusline.py"))
conf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(conf)


def state(settings):
    if not os.path.isdir(os.path.dirname(settings)):
        return "absent"
    try:
        data = json.load(io.open(settings, encoding="utf-8"))
    except (OSError, ValueError):
        return "unwired"
    line = data.get("statusLine") if isinstance(data, dict) else None
    command = line.get("command", "") if isinstance(line, dict) else ""
    if not isinstance(command, str) or not command:
        return "unwired"
    if conf.MARKER in command:
        return "wired"
    if conf.LEGACY_MARKER in conf._read(conf.existing_script(command)):
        return "wired"
    return "unwired"


def main(argv):
    settings = os.path.expanduser("~/.claude/settings.json")
    if len(argv) == 3 and argv[1] == "--settings":
        settings = os.path.expanduser(argv[2])
    elif len(argv) != 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    print(state(settings))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
