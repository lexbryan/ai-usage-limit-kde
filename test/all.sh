#!/usr/bin/env bash
# Every suite. None needs a Plasma session or touches a live install.
# (tools/screenshots.sh is the one check that does need Plasma: it renders the
# widget in a nested KWin and fails on any QML warning.)
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
rc=0

echo "── logic.test.mjs (node) ─────────────────────────────"
node --test "$here"/*.test.mjs 2>&1 | grep -E '^(not )?ok|^# (pass|fail)' || rc=1
node --test "$here"/*.test.mjs >/dev/null 2>&1 || rc=1
echo

for suite in test-wrapper.sh test-configure.sh test-codex.sh test-connect.sh test-package.sh; do
    echo "── $suite ──────────────────────────────────────────"
    "$here/$suite" || rc=1
    echo
done
[ "$rc" -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
exit "$rc"
