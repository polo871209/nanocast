#!/bin/bash
set -euo pipefail

BODY_OUT="${1:?usage: release-notes.sh <body.md>}"

REPO="${REPO:-polo871209/nanocast}"
TAG="${TAG:?TAG is required, e.g. v0.9.13}"
SHA="${SHA:-$(git rev-parse HEAD)}"
VERSION="${VERSION:-${TAG#v}}"

MARKER="<!-- nanocast:install -->"

PREVIOUS="$(gh release list --repo "$REPO" --limit 200 --json tagName,isDraft --jq \
    "[.[] | select(.isDraft | not) | .tagName | select(. != \"${TAG}\")] | first // empty")"

NOTES_ARGS=(-f "tag_name=${TAG}" -f "target_commitish=${SHA}")
if [ -n "$PREVIOUS" ]; then NOTES_ARGS+=(-f "previous_tag_name=${PREVIOUS}"); fi
echo "▸ Generating notes for ${TAG}${PREVIOUS:+ since ${PREVIOUS}}"
GENERATED="$(gh api "repos/${REPO}/releases/generate-notes" "${NOTES_ARGS[@]}" --jq .body)"

COMPARE_URL="$(printf '%s\n' "$GENERATED" | sed -n 's|^\*\*Full Changelog\*\*: \(.*\)$|\1|p' | tail -n1)"

# A bare `#304` autolinks on the web and fits the 460pt update window; the full URL does neither.
CHANGELOG="$(printf '%s\n' "$GENERATED" | sed -E \
    -e '/^\*\*Full Changelog\*\*:/d' \
    -e "s|https://github\.com/${REPO}/pull/([0-9]+)|#\1|g")"
[ -n "$(printf '%s' "$CHANGELOG" | tr -d '[:space:]')" ] || CHANGELOG="Maintenance and internal changes."

{
    printf '%s\n\n' "$CHANGELOG"
    printf '%s\n\n' "$MARKER"
    printf '**Version:** %s\n' "$VERSION"
    printf 'Built from %s.' "$SHA"
    if [ -n "$COMPARE_URL" ]; then printf ' [Full changelog](%s)' "$COMPARE_URL"; fi
    printf '\n\n'
    printf '%s\n' "**Recommended:** install via Homebrew — it clears the quarantine flag automatically on every install and update, so there's nothing to run by hand:"
    cat <<'SH'
```sh
brew tap polo871209/nanocast https://github.com/polo871209/nanocast
brew trust --tap polo871209/nanocast
brew install --cask polo871209/nanocast/nanocast
```
SH
    printf '%s\n' "This build is self-signed. If you download the DMG directly instead of using Homebrew, macOS will refuse to open it until you clear the quarantine flag once:"
    cat <<'SH'
```sh
xattr -dr com.apple.quarantine /Applications/Nanocast.app
```
SH
} > "$BODY_OUT"

echo "✓ ${BODY_OUT}"
