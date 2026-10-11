#!/bin/bash
set -euo pipefail

ROOT="$(cd "${1:-$(dirname "$0")/..}" && pwd -P)"
TAP="polo871209/nanocast"
TAP_DIR="$(brew --repository)/Library/Taps/polo871209/homebrew-nanocast"

if [ -e "$TAP_DIR" ] && [ "$(readlink "$TAP_DIR")" != "$ROOT" ]; then
    echo "✗ ${TAP_DIR} already holds another copy of the tap. Remove it with: brew untap ${TAP}" >&2
    exit 1
fi

mkdir -p "$(dirname "$TAP_DIR")"
ln -sfn "$ROOT" "$TAP_DIR"
brew trust --tap "$TAP" >/dev/null
echo "✓ ${TAP} -> ${ROOT}"
