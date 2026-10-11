#!/bin/bash
set -euo pipefail

# shellcheck disable=SC2016
RENAME='
    s#abue-ammar/(homebrew-)?tinycast#abue-ammar/${1}__UPSTREAM_REPO__#g;
    s/tinycast\.dev/__UPSTREAM_SITE__/g;
    s/hello tinycast/__AES_PLAINTEXT__/g;
    s/Tinycast/Nanocast/g; s/tinycast/nanocast/g; s/TINYCAST/NANOCAST/g;
    s#__UPSTREAM_REPO__#tinycast#g; s/__UPSTREAM_SITE__/tinycast.dev/g; s/__AES_PLAINTEXT__/hello tinycast/g;
'

if [ "${1:-}" = "--stdin" ]; then
    exec perl -pe "$RENAME"
fi

TREE="${1:?usage: rename-upstream.sh <tree> | --stdin}"
command -v xcodegen >/dev/null || { echo "✗ xcodegen is required: brew install xcodegen" >&2; exit 1; }
cd "$TREE"

is_fork_script() {
    [ "$1" = "Scripts/rename-upstream.sh" ] || [ "$1" = "Scripts/sync-upstream.sh" ] ||
        [ "$1" = "Scripts/port-upstream.sh" ]
}

files_naming_tinycast() {
    git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' path; do
        if [ -f "$path" ] && ! is_fork_script "$path" && grep -Iqi tinycast -- "$path"; then
            printf '%s\0' "$path"
        fi
    done
}

files_naming_tinycast | xargs -0 perl -pi -e "$RENAME"

rm -rf Tinycast.xcodeproj
find . -depth -iname '*tinycast*' -not -path './.git/*' -not -path './build/*' -not -path '*/node_modules/*' |
    while IFS= read -r path; do
        base="$(basename "$path" | sed -e 's/Tinycast/Nanocast/g' -e 's/tinycast/nanocast/g' -e 's/TINYCAST/NANOCAST/g')"
        mv "$path" "$(dirname "$path")/$base"
    done

xcodegen generate --quiet
