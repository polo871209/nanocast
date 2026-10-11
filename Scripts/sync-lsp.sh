#!/bin/bash

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

LOG=${1:-}
if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
    echo "usage: $0 <xcodebuild-log>" >&2
    exit 2
fi
command -v xcode-build-server >/dev/null || { echo "xcode-build-server not installed; skipping." >&2; exit 0; }

backup="${TMPDIR:-/tmp}/nanocast-compile.bak"
[ -f .compile ] && cp .compile "$backup"

# Only `parse` without `-o` writes buildServer.json as `kind: manual`, and `kind: xcode` ignores .compile.
xcode-build-server parse < "$LOG" >/dev/null 2>&1

if [ ! -s .compile ] || ! grep -q '"command"' .compile 2>/dev/null; then
    if [ -f "$backup" ]; then
        cp "$backup" .compile
        echo "no compile commands in log; kept the previous .compile" >&2
    fi
fi
rm -f "$backup"

./Scripts/run-tests.sh --index
