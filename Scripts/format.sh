#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

FORMAT=$(xcrun --find swift-format 2>/dev/null)
[ -x "${FORMAT:-}" ] || {
    echo "✗ swift-format not found in the Xcode toolchain. Check 'xcode-select -p'." >&2
    exit 2
}

# Built with a read loop rather than `mapfile`, which is bash 4 — macOS ships bash 3.2.
files=()
while IFS= read -r f; do files+=("$f"); done < <(
    find Nanocast Tests -name '*.swift' ! -name '*.generated.swift' \
        ! -path 'Nanocast/DesignSystem/Scrolling/EdgeDissolve.swift' \
        ! -path 'Nanocast/DesignSystem/Scrolling/ThinScrollbar.swift' | sort
)

if [ "${1:-}" = "--check" ]; then
    dirty=()
    for f in "${files[@]}"; do
        "$FORMAT" --configuration .swift-format "$f" 2>/dev/null | diff -q - "$f" >/dev/null 2>&1 || dirty+=("$f")
    done
    if [ ${#dirty[@]} -gt 0 ]; then
        printf '%s\n' "${dirty[@]}"
        echo
        echo "${#dirty[@]} file(s) need formatting. Run ./Scripts/format.sh" >&2
        exit 1
    fi
    echo "✓ format-clean (${#files[@]} files)"
    exit 0
fi

failed=()
for f in "${files[@]}"; do
    "$FORMAT" --configuration .swift-format --in-place "$f" || failed+=("$f")
done

if [ ${#failed[@]} -gt 0 ]; then
    printf '\n%d file(s) could not be formatted (they do not parse):\n' "${#failed[@]}" >&2
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
echo "✓ formatted ${#files[@]} files"
