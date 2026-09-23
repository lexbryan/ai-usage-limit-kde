#!/usr/bin/env python3
"""Point Claude Code's statusLine at the publish-and-forward wrapper.

Claude Code hands the rate limits to the statusLine command and to nothing else,
so something in that position has to record them. This wraps whatever you
already have instead of editing it:

    "command": "bash /path/aiul-statusline.sh <your original command>"

Four cases, all idempotent:

  already wrapped          leave alone
  statusline publishes     leave alone (an in-place patch already does the job)
  a statusline exists      wrap it, preserving the original command verbatim
  no statusline            install the wrapper on its own

Usage: configure-statusline.py <wrapper-path> [--settings PATH] [--dry-run]
"""
import io
import json
import os
import shutil
import sys
import time

MARKER = "aiul-statusline.sh"
# The marker left by the older in-place patch, kept so an existing install that
# used it is recognised and not double-wrapped.
LEGACY_MARKER = "aiul_cache"


def quote(path):
    """Quote a path for a shell command line, only when it needs it."""
    if path and all(c.isalnum() or c in "./_-~+=:@" for c in path):
        return path
    return "'" + path.replace("'", "'\\''") + "'"


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    wrapper = os.path.abspath(argv[1])
    settings = os.path.expanduser("~/.claude/settings.json")
    dry = False
    rest = argv[2:]
    while rest:
        a = rest.pop(0)
        if a == "--dry-run":
            dry = True
        elif a == "--settings" and rest:
            settings = os.path.expanduser(rest.pop(0))
        else:
            print("unknown argument: %s" % a, file=sys.stderr)
            return 2

    if not os.path.exists(wrapper):
        print("wrapper not found: %s" % wrapper, file=sys.stderr)
        return 1

    if os.path.exists(settings):
        try:
            data = json.load(io.open(settings, encoding="utf-8"))
        except ValueError as e:
            print("%s is not valid JSON (%s) — not touching it." % (settings, e),
                  file=sys.stderr)
            return 1
        if not isinstance(data, dict):
            print("%s is not a JSON object — not touching it." % settings,
                  file=sys.stderr)
            return 1
    else:
        data = {}

    line = data.get("statusLine")
    existing = line.get("command", "") if isinstance(line, dict) else ""

    if MARKER in existing:
        print("statusLine already goes through the wrapper — left alone")
        return 0

    # An existing statusline that publishes the cache itself (the older in-place
    # patch) already does this job; wrapping would just write the file twice.
    if existing and LEGACY_MARKER in _read(existing_script(existing)):
        print("your statusline already publishes the cache — left alone")
        return 0

    if existing:
        command = "bash %s %s" % (quote(wrapper), existing)
        what = "wrapping your existing statusline"
    else:
        command = "bash %s" % quote(wrapper)
        what = "installing the wrapper as your statusline"

    new_line = dict(line) if isinstance(line, dict) else {}
    new_line["type"] = "command"
    new_line["command"] = command
    data["statusLine"] = new_line

    print("%s:\n  %s" % (what, command))
    if dry:
        print("(dry run — %s not written)" % settings)
        return 0

    os.makedirs(os.path.dirname(settings), exist_ok=True)
    if os.path.exists(settings):
        backup = "%s.bak-aiul-%s" % (settings, time.strftime("%Y%m%d-%H%M%S"))
        shutil.copy2(settings, backup)
        print("  backed up to %s" % backup)

    tmp = settings + ".tmp-aiul"
    with io.open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, settings)
    print("  wrote %s" % settings)
    return 0


def existing_script(command):
    """Best-effort: the script file an existing statusLine command runs."""
    for token in command.split():
        if token.endswith(".sh") or "/" in token and os.path.isfile(
                os.path.expanduser(token)):
            return os.path.expanduser(token)
    return ""


def _read(path):
    if not path or not os.path.isfile(path):
        return ""
    try:
        return io.open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


if __name__ == "__main__":
    sys.exit(main(sys.argv))
