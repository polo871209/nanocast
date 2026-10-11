#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

command -v swiftlint >/dev/null || {
    echo "✗ swiftlint not found. Install it with:  brew install swiftlint" >&2
    exit 2
}

if [ "${1:-}" = "--fix" ]; then
    swiftlint --fix --quiet
    ./Scripts/format.sh || exit 1
fi

if ! swiftlint lint --strict --quiet; then
    echo
    echo "Lint violations above. Every violation blocks." >&2
    exit 1
fi
if ! ./Scripts/format.sh --check; then
    exit 1
fi
if ! node Scripts/check-settings-search.js; then
    exit 1
fi

echo "✓ lint-clean"
