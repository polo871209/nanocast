#!/bin/bash
set -uo pipefail

APP="${1:?usage: verify-signature.sh <path-to-.app>}"
NAME="$(basename "$APP" .app)"
STATUS=0

# tccd denies a usage request silently when its hardened-runtime entitlement is missing.
RESOURCE_ENTITLEMENTS=(
    NSAppleEventsUsageDescription=com.apple.security.automation.apple-events
    NSCameraUsageDescription=com.apple.security.device.camera
    NSMicrophoneUsageDescription=com.apple.security.device.audio-input
    NSCalendarsFullAccessUsageDescription=com.apple.security.personal-information.calendars
    NSCalendarsWriteOnlyAccessUsageDescription=com.apple.security.personal-information.calendars
    NSRemindersFullAccessUsageDescription=com.apple.security.personal-information.calendars
    NSContactsUsageDescription=com.apple.security.personal-information.addressbook
    NSLocationWhenInUseUsageDescription=com.apple.security.personal-information.location
    NSPhotoLibraryUsageDescription=com.apple.security.personal-information.photos-library
)

fail() {
    echo "✗ $1" >&2
    STATUS=1
}

ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null

for BIN in "$APP/Contents/MacOS/$NAME" "$APP/Contents/Helpers/ClipboardTextHelper" "$APP/Contents/Helpers/FileIndexHelper"; do
    INFO="$(codesign -dv --verbose=2 "$BIN" 2>&1)"
    [[ "$INFO" =~ flags=0x[0-9a-f]+\([^\)]*runtime ]] ||
        fail "${BIN##*/}: hardened runtime not enabled"
done

codesign --verify --deep --strict "$APP" || fail "$NAME.app: the seal does not verify"

# Xcode injects it for Debug only; notarization refuses any build still carrying it.
/usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$ENTITLEMENTS" &>/dev/null &&
    fail "$NAME.app: get-task-allow is present"

for PAIR in "${RESOURCE_ENTITLEMENTS[@]}"; do
    USAGE="${PAIR%%=*}" ENTITLEMENT="${PAIR#*=}"
    /usr/libexec/PlistBuddy -c "Print :$USAGE" "$APP/Contents/Info.plist" &>/dev/null || continue
    [ "$(/usr/libexec/PlistBuddy -c "Print :$ENTITLEMENT" "$ENTITLEMENTS" 2>/dev/null)" = true ] ||
        fail "$NAME.app: $USAGE is declared but $ENTITLEMENT is not"
done

if [ "$STATUS" -eq 0 ]; then
    echo "✓ $NAME.app is notarizable and its prompts are entitled"
fi
exit "$STATUS"
