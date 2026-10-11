#!/bin/bash

set -uo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/nanocast-harness"
SWIFT_FLAGS=(-swift-version 6 -enable-upcoming-feature MemberImportVisibility)
mkdir -p "$BIN"

if [ "${1:-}" = "--exec" ]; then
    shift
    name=$1 opt=$2
    shift 2
    : > "$BIN/$name.running"
    trap 'rm -f "$BIN/$name.running" "$BIN/$name.time"' EXIT
    fail() {
        printf '\033[31mFAIL\033[0m  %-25s %s\n' "$name" "$1"
        : > "$BIN/$name.failed"
        exit 0
    }
    TIMEFORMAT=%1R
    if ! compiled=$( { time swiftc "${SWIFT_FLAGS[@]}" "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2>&1 ); then
        fail "did not compile"
    fi
    { time "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2> "$BIN/$name.time" &
    pid=$!
    # macOS ships no `timeout`, so the worker polls; a wedged harness must fail, not stall.
    ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((NANOCAST_TEST_TIMEOUT * 5)) ]; then
            { pkill -KILL -P "$pid"; kill -KILL "$pid"; wait "$pid"; } 2>/dev/null
            printf '\n[run-tests] killed after %ss without finishing\n' "$NANOCAST_TEST_TIMEOUT" >> "$BIN/$name.log"
            fail "timed out after ${NANOCAST_TEST_TIMEOUT}s"
        fi
        ticks=$((ticks + 1))
        sleep 0.2
    done
    wait "$pid"
    status=$?
    took=$(< "$BIN/$name.time")
    if [ "$status" -gt 128 ]; then fail "crashed (signal $((status - 128))) after ${took}s"; fi
    if [ "$status" -ne 0 ]; then fail "assertion failed after ${took}s"; fi
    printf '\033[32mok\033[0m    %-25s %5ss  \033[2m(compile %ss)\033[0m\n' "$name" "$took" "$compiled"
    exit 0
fi

QUEUE="$BIN/queue"
: > "$QUEUE"
rm -f "$BIN"/*.failed "$BIN"/*.running

failed=()
ran=0
only="${1:-}"

emit_db=0
DB="${TMPDIR:-/tmp}/nanocast-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

run() {
    local opt=-Onone pri=1 index_only=0
    while :; do
        case "$1" in
            slow)  pri=0; shift;;
            -O)    opt=-O; shift;;
            index) index_only=1; shift;;
            *)     break;;
        esac
    done
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    if [ "$index_only" -eq 1 ] && [ "$emit_db" -eq 0 ]; then return 0; fi
    ran=$((ran + 1))

    # Absolute paths: sourcekit-lsp ignores `directory` for relative arguments and indexes nothing.
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc %s -sdk %s' \
            "$PWD" "${SWIFT_FLAGS[*]}" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

L=Nanocast/Features/Launcher/Model
run slow -O fuzz-test      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift
run link-destination-test  $L/LinkDestination.swift
FS=Nanocast/Features/FileSearch
FILE_INDEX="$FS/Service/FileIndex.swift $FS/Service/FileIndexSnapshot.swift $FS/Service/FileIndexCrawler.swift"
run file-search-test       $FS/Model/*.swift
run file-index-test        $FS/Model/*.swift $FILE_INDEX
run file-search-session-test $FS/Model/*.swift $FS/Service/FileSearchSession.swift $FILE_INDEX
run menu-search-test       $L/SearchRelevance.swift \
                           Nanocast/Features/MenuSearch/Model/*.swift \
                           Nanocast/Features/MenuSearch/Service/*.swift
run window-switch-test     Nanocast/Features/WindowSwitcher/Model/*.swift
run index file-search-performance $FS/Model/*.swift $FILE_INDEX
run ranking-test           $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift
run app-name-test          Nanocast/Platform/AppDisplayName.swift \
                           Nanocast/Platform/BundleLocalization.swift \
                           $L/SearchRelevance.swift
run favorites-test         $L/FavoriteSlots.swift
run app-installation-test  $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift $L/SearchScopes.swift \
                           Nanocast/Features/Launcher/Service/AppIndex.swift \
                           Nanocast/Features/Launcher/Service/AppLauncher.swift \
                           Nanocast/Features/Launcher/Service/RunningAppsMonitor.swift \
                           Nanocast/Features/Launcher/Service/FavoritesStore.swift \
                           Nanocast/Features/Launcher/Service/AliasStore.swift \
                           Nanocast/Features/Launcher/Service/VisibilityStore.swift \
                           Nanocast/Features/Launcher/Service/BundleNameCache.swift \
                           Nanocast/Platform/AppDisplayName.swift Nanocast/Platform/BundleLocalization.swift \
                           Nanocast/Platform/SystemLanguages.swift \
                           Nanocast/Platform/Images/FileIconStamp.swift Nanocast/Platform/Memo.swift \
                           Nanocast/Platform/Signposts.swift Nanocast/Platform/NotificationToken.swift
run launcher-file-test     $L/LauncherFileFormat.swift \
                           Nanocast/Features/Settings/Model/SettingsFileJSON.swift
run launcher-settings-file-test \
                           $L/LauncherFileFormat.swift $L/CommandID.swift $L/CommandCatalog.swift \
                           $L/LinkDestination.swift \
                           Nanocast/Features/Launcher/Service/LauncherSettingsFile.swift \
                           Nanocast/Features/Launcher/Service/AliasStore.swift \
                           Nanocast/Features/Launcher/Service/VisibilityStore.swift \
                           Nanocast/Features/Settings/SettingsTab.swift \
                           Nanocast/Features/Settings/Model/*.swift \
                           Nanocast/Features/HotKeys/Service/HotKeySettingsFile.swift \
                           Nanocast/Features/HotKeys/Service/KeyShortcut.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyAction.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Nanocast/Features/HotKeys/Model/HotKeySpelling.swift \
                           Nanocast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Nanocast/Features/HotKeys/Model/ModifierKey.swift \
                           Nanocast/Features/HotKeys/Model/HyperKey.swift \
                           Nanocast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Nanocast/Platform/ASCIIKeyboardLayout.swift \
                           Nanocast/Features/SystemActions/Model/SystemAction.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCommand.swift
run calc-test              Nanocast/Features/Calculator/Model/*.swift
run index calc-performance Nanocast/Features/Calculator/Model/*.swift
run clipboard-test         Nanocast/Features/Clipboard/Model/ClipboardStore.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorFormat.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift
run clipboard-thumbnail-test Nanocast/Features/Clipboard/Model/ClipboardStore.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorFormat.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift \
                           Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Platform/Images/ImageThumbnail.swift \
                           Nanocast/Platform/Images/ThumbnailCache.swift
Q=$L/LinkDestination.swift
run clipboard-search-test  Nanocast/Features/Clipboard/Model/*.swift Nanocast/Platform/Images/ImageDerivative.swift $Q
run paste-sequence-test    Nanocast/Features/Clipboard/Model/*.swift Nanocast/Platform/Images/ImageDerivative.swift $Q
run clipboard-text-test    Nanocast/Features/Clipboard/Model/*.swift Nanocast/Platform/Images/ImageDerivative.swift $Q \
                           Nanocast/Features/Clipboard/Service/ClipboardTextExtractor.swift \
                           Nanocast/Features/Clipboard/Service/ClipboardTextIndexer.swift \
                           Nanocast/Features/Clipboard/Service/ClipboardTextWorker.swift \
                           Nanocast/Platform/ProcessExit.swift
run pasteboard-test        Nanocast/Platform/PasteboardFiles.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardStore.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorFormat.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift \
                           Nanocast/Features/Clipboard/Service/ClipboardManager.swift \
                           Nanocast/Features/Clipboard/Service/Paster.swift
run index clipboard-file-performance \
                           Nanocast/Platform/PasteboardFiles.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardStore.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorFormat.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift \
                           Nanocast/Features/Clipboard/Service/ClipboardManager.swift
run index clipboard-thumbnail-performance \
                           Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Platform/Images/ImageThumbnail.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Platform/Images/ThumbnailCache.swift
run emoji-test             Nanocast/Features/Emoji/Model/EmojiCatalog.swift \
                           Nanocast/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Nanocast/Features/Emoji/Model/EmojiData.generated.swift
run emoji-search-test      Nanocast/Features/Emoji/Model/EmojiCatalog.swift \
                           Nanocast/Features/Emoji/Model/EmojiData.generated.swift \
                           Nanocast/Features/Emoji/Service/EmojiIndex.swift \
                           Nanocast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Nanocast/Features/Emoji/Service/PinnedEmojiStore.swift \
                           Nanocast/Features/Launcher/Model/SearchRelevance.swift \
                           Nanocast/Platform/AppPaths.swift Nanocast/Platform/Memo.swift
run index emoji-search-performance \
                           Nanocast/Features/Emoji/Model/EmojiCatalog.swift \
                           Nanocast/Features/Emoji/Model/EmojiData.generated.swift \
                           Nanocast/Features/Emoji/Service/EmojiIndex.swift \
                           Nanocast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Nanocast/Features/Launcher/Model/SearchRelevance.swift \
                           Nanocast/Platform/AppPaths.swift Nanocast/Platform/Memo.swift
run palette-selection-test Nanocast/Features/PaletteRowIndex.swift \
                           Nanocast/Features/Emoji/Model/EmojiGridGeometry.swift
run appearance-test        Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Features/Settings/AppAppearance.swift
run language-test          Nanocast/Features/Settings/AppLanguage.swift
run relaunch-test          Nanocast/App/AppDelegate.swift Nanocast/Platform/RelaunchRunner.swift
run interface-size-test    Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Features/Settings/InterfaceSize.swift
run palette-placement-test Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Features/Settings/InterfaceSize.swift \
                           Nanocast/Palette/PalettePlacement.swift
run palette-menu-click-test Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/Platform/WindowLevel.swift \
                           Nanocast/Platform/NotificationToken.swift \
                           Nanocast/DesignSystem/Interaction/KeyboardFocus.swift \
                           Nanocast/Palette/PalettePanel.swift
run form-input-test        Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/DesignSystem/FormTextInput.swift \
                           Nanocast/DesignSystem/FormTextArea.swift
run scroll-reveal-test     Nanocast/DesignSystem/Scrolling/SelectionReveal.swift
run keyboard-focus-test    Nanocast/DesignSystem/Interaction/KeyboardFocus.swift
run palette-escape-test    Nanocast/Palette/PaletteMode.swift \
                           Nanocast/Palette/PaletteEscapeAction.swift \
                           Nanocast/Palette/CommandEscapeTap.swift \
                           Nanocast/Features/Settings/EscapeKeyBehavior.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift
run palette-navigation-test Nanocast/Palette/PaletteState.swift \
                           Nanocast/Palette/PaletteMode.swift \
                           Nanocast/Palette/HoverArming.swift \
                           Nanocast/Features/Emoji/Model/EmojiCatalog.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardStore.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Nanocast/Features/FileSearch/Model/FileSearchFilter.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorFormat.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift
run palette-filter-test    Nanocast/Palette/PaletteMode.swift \
                           Nanocast/Palette/PaletteFilterAction.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift
run action-menu-search-test Nanocast/Palette/ActionMenuSearchQuery.swift \
                            Nanocast/Features/Launcher/Model/SearchRelevance.swift
run palette-shortcut-test  Nanocast/Palette/PaletteShortcut.swift
run ascii-layout-test      Nanocast/Platform/ASCIIKeyboardLayout.swift
run palette-tab-test       Nanocast/Palette/PaletteMode.swift \
                           Nanocast/Palette/PaletteTabAction.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift
run dictionary-test        Nanocast/Features/Dictionary/Model/DictionaryEntry.swift \
                           Nanocast/Features/Dictionary/Model/DictionaryMarkup.swift
run dictation-test         Nanocast/Features/Dictation/Model/DictationModel.swift Nanocast/Features/Dictation/Model/DictationIdleRelease.swift Nanocast/Features/Dictation/Model/DictationLanguage.swift Nanocast/Features/Dictation/Model/DictationTextFormatter.swift
run dictation-volume-test  Nanocast/Features/Dictation/Model/DictationVolumeSnapshot.swift \
                           Nanocast/Features/Dictation/Service/DictationAudioDucker.swift \
                           Nanocast/Platform/AppPaths.swift
run index -O dictation-performance Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Features/Dictation/Model/DictationModel.swift \
                           Nanocast/Features/Dictation/Service/DictationWire.swift
run dictation-inference-test Nanocast/Features/Dictation/Model/DictationAudioChunks.swift \
    Nanocast/Features/Dictation/Service/DictationSpectrum.swift \
    Nanocast/Features/Dictation/Helper/DictationTensor.swift Nanocast/Features/Dictation/Helper/DictationTokenizer.swift \
    Nanocast/Features/Dictation/Helper/DictationMel.swift
run dictation-worker-test  Nanocast/Features/Dictation/Model/DictationModel.swift \
                           Nanocast/Features/Dictation/Model/DictationIdleRelease.swift \
                           Nanocast/Features/Dictation/Service/DictationWire.swift \
                           Nanocast/Features/Dictation/Service/DictationWorker.swift \
                           Nanocast/Features/Dictation/Service/DictationModelStore.swift \
                           Nanocast/Features/Dictation/Service/DictationModelDownloader.swift \
                           Nanocast/Platform/ProcessExit.swift Nanocast/Platform/AppPaths.swift
run hotkey-test            Nanocast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Nanocast/Features/HotKeys/Model/ModifierKey.swift \
                           Nanocast/Features/HotKeys/Model/ModifierKeyDetector.swift \
                           Nanocast/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Nanocast/Features/HotKeys/Model/HotKeySpelling.swift \
                           Nanocast/Features/HotKeys/Model/HyperKey.swift \
                           Nanocast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Nanocast/Platform/ASCIIKeyboardLayout.swift \
                           Nanocast/Features/HotKeys/Service/KeyShortcut.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyAction.swift \
                           Nanocast/Features/Launcher/Model/CommandID.swift \
                           Nanocast/Features/SystemActions/Model/SystemAction.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCommand.swift
run callout-test          Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Features/HotKeys/UI/CalloutPlacement.swift
run icon-cache-test        Nanocast/Platform/Appearance.swift \
                           Nanocast/Platform/Images/IconCache.swift
run entry-icon-test        Nanocast/Platform/Appearance.swift \
                           Nanocast/Platform/Images/IconCache.swift \
                           Nanocast/Platform/Images/FileIconStamp.swift
run system-action-test     Nanocast/Features/SystemActions/Model/SystemAction.swift
run microphone-mute-test   Nanocast/Features/SystemActions/Service/SystemActionFailure.swift \
                           Nanocast/Features/SystemActions/Service/SystemActionRunner+Microphone.swift
run volume-test            Nanocast/Features/SystemActions/Model/VolumeLevel.swift
run window-command-test    Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCycle.swift \
                           Nanocast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Nanocast/Features/WindowManagement/Model/WindowActionMemory.swift
run window-preset-test     Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/WindowManagement/Model/WindowShortcutPreset.swift \
                           Nanocast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Nanocast/Features/HotKeys/Model/ModifierKey.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Nanocast/Features/HotKeys/Model/HyperKey.swift \
                           Nanocast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Nanocast/Platform/ASCIIKeyboardLayout.swift \
                           Nanocast/Features/HotKeys/Service/KeyShortcut.swift
run space-gesture-test     Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/WindowManagement/Model/SpaceGesture.swift
run window-layout-test     Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCycle.swift \
                           Nanocast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayout.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutStore.swift \
                           Nanocast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Nanocast/Features/WindowManagement/Model/CustomWindowSizeStore.swift
run window-room-test       Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCycle.swift \
                           Nanocast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayout.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Nanocast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Nanocast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Nanocast/Features/WindowManagement/Model/RoomGrid.swift \
                           Nanocast/Features/WindowManagement/Model/RoomWindow.swift \
                           Nanocast/Features/WindowManagement/Model/Room.swift \
                           Nanocast/Features/WindowManagement/Model/RoomWindowMatcher.swift \
                           Nanocast/Features/WindowManagement/Model/RoomParking.swift \
                           Nanocast/Features/WindowManagement/Model/RoomPlan.swift \
                           Nanocast/Features/WindowManagement/Model/RoomArrangement.swift \
                           Nanocast/Features/WindowManagement/Model/RoomStore.swift \
                           Nanocast/Features/WindowManagement/Model/RoomMinimumSizeStore.swift \
                           Nanocast/Features/WindowManagement/Model/RoomParkingLedger.swift
run window-file-test       Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCycle.swift \
                           Nanocast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayout.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Nanocast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Nanocast/Features/WindowManagement/Model/Room.swift \
                           Nanocast/Features/WindowManagement/Model/RoomWindow.swift \
                           Nanocast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Nanocast/Features/WindowManagement/Model/RoomGrid.swift \
                           Nanocast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Nanocast/Features/WindowManagement/Model/WindowManagementFileFormat.swift \
                           Nanocast/Features/Settings/Model/SettingsFileJSON.swift \
                           Nanocast/Features/Settings/Model/SettingsFileIdentity.swift
run custom-command-test    Nanocast/Platform/PseudoTerminal.swift \
                           Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift \
                           Nanocast/Features/CustomCommands/Model/RaycastScriptImport.swift \
                           Nanocast/Features/CustomCommands/UI/CustomCommandEditorSession.swift \
                           Nanocast/Features/CustomCommands/Service/ShellCommandRunner.swift
run custom-command-list-test Nanocast/Features/CustomCommands/Model/CustomCommand.swift \
                             Nanocast/Features/CustomCommands/UI/CustomCommandListScreen.swift
run uninstall-coordinator-test Nanocast/Features/Uninstall/Model/*.swift \
                           Nanocast/Features/Uninstall/UI/UninstallCoordinator.swift
run uninstall-test         Nanocast/Features/Uninstall/Model/UninstallTarget.swift \
                           Nanocast/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Nanocast/Features/Uninstall/Model/UninstallRules.swift \
                           Nanocast/Features/Uninstall/Model/UninstallProtection.swift \
                           Nanocast/Features/Uninstall/Model/UninstallPlan.swift
run text-injection-test    Nanocast/Platform/AccessibilityText.swift \
                           Nanocast/Features/TextInjection/Service/*.swift
run notes-test             Nanocast/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Nanocast/Features/Notes/Model/*.swift \
                           Nanocast/Features/Notes/Service/*.swift
run notes-editor-test      Nanocast/Platform/Signposts.swift \
                           Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Platform/NotificationToken.swift \
                           Nanocast/Features/TextInjection/Service/InjectableTextView.swift \
                           Nanocast/Features/Notes/Model/NoteDocument.swift \
                           Nanocast/Features/Notes/Model/NoteMarkdown.swift \
                           Nanocast/Features/Notes/Model/NoteMarkdownParser.swift \
                           Nanocast/Features/Notes/Model/NoteInlineScanner.swift \
                           Nanocast/Features/Notes/Model/NoteEditPlan.swift \
                           Nanocast/Features/Notes/Model/NoteEditAction.swift \
                           Nanocast/Features/Notes/Model/NoteFormatting.swift \
                           Nanocast/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Nanocast/Features/Notes/Model/NoteRevealPolicy.swift \
                           Nanocast/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Nanocast/Features/Notes/UI/NoteBlockDecoration.swift \
                           Nanocast/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Nanocast/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Nanocast/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Nanocast/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Nanocast/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Nanocast/Features/Notes/UI/NoteTextViewEditing.swift \
                           Nanocast/Features/Notes/UI/NoteTextView.swift \
                           Nanocast/Features/Notes/UI/NoteEditorView.swift
run -O index notes-editor-performance \
                           Nanocast/Platform/Signposts.swift \
                           Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Platform/NotificationToken.swift \
                           Nanocast/Features/TextInjection/Service/InjectableTextView.swift \
                           Nanocast/Features/Notes/Model/NoteDocument.swift \
                           Nanocast/Features/Notes/Model/NoteMarkdown.swift \
                           Nanocast/Features/Notes/Model/NoteMarkdownParser.swift \
                           Nanocast/Features/Notes/Model/NoteInlineScanner.swift \
                           Nanocast/Features/Notes/Model/NoteEditPlan.swift \
                           Nanocast/Features/Notes/Model/NoteEditAction.swift \
                           Nanocast/Features/Notes/Model/NoteFormatting.swift \
                           Nanocast/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Nanocast/Features/Notes/Model/NoteRevealPolicy.swift \
                           Nanocast/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Nanocast/Features/Notes/UI/NoteBlockDecoration.swift \
                           Nanocast/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Nanocast/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Nanocast/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Nanocast/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Nanocast/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Nanocast/Features/Notes/UI/NoteTextViewEditing.swift \
                           Nanocast/Features/Notes/UI/NoteTextView.swift \
                           Nanocast/Features/Notes/UI/NoteEditorView.swift
run slow -O raycast-test   Nanocast/Features/Backup/Model/RaycastImportError.swift \
                           Nanocast/Features/Backup/Service/RaycastDecoder.swift \
                           Nanocast/Features/Backup/Service/Scrypt.swift \
                           Nanocast/Platform/Compression/Zlib.swift \
                           Nanocast/Features/Clipboard/Model/RaycastClipboardImport.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardStore.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorFormat.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift
run settings-backup-test   Nanocast/Features/Settings/AppSettingsKey.swift \
                           Nanocast/Features/Backup/Model/SettingsBackupCoverage.swift
run hyper-key-test         Nanocast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Nanocast/Features/HotKeys/Model/HyperKeyConflictPolicy.swift \
                           Nanocast/Features/HotKeys/Service/KeyboardRemapper.swift \
                           Tests/hyper-key-fixtures.swift
run hotkey-dispatch-test   Nanocast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Nanocast/Features/HotKeys/Model/ModifierKey.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Nanocast/Features/HotKeys/Model/HyperKey.swift \
                           Nanocast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyAction.swift \
                           Nanocast/Features/HotKeys/Service/KeyShortcut.swift \
                           Nanocast/Features/HotKeys/Service/HotKeyManager.swift \
                           Nanocast/Platform/ASCIIKeyboardLayout.swift \
                           Tests/hotkey-dispatch-fixtures.swift
run settings-file-test     Nanocast/Features/Settings/Model/*.swift \
                           Nanocast/Features/Settings/Service/SettingsFileMonitor.swift \
                           Nanocast/Features/Settings/Service/SettingsFileRepository.swift \
                           Nanocast/Platform/AppPaths.swift
run backup-archive-test    Nanocast/Platform/AppPaths.swift \
                           Nanocast/Features/Backup/Model/BackupArchive.swift \
                           Nanocast/Features/Backup/Model/BackupBundle.swift \
                           Nanocast/Features/Backup/Model/BackupCategory.swift \
                           Nanocast/Features/Backup/Model/BackupClipboardItem.swift \
                           Nanocast/Features/Backup/Model/BackupManifest.swift \
                           Nanocast/Features/Backup/Service/BackupStaging.swift
run settings-history-test  Nanocast/Features/Settings/SettingsTab.swift \
                           Nanocast/Features/Settings/SettingsHistory.swift \
                           Nanocast/Features/Settings/SettingsAnchor.swift \
                           Nanocast/Features/Settings/SettingsNavigationState.swift \
                           Nanocast/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift
run updates-test           Nanocast/Features/Updates/Model/*.swift \
                           Nanocast/Features/Updates/Service/BundleSignature.swift
run update-check-test      Nanocast/Features/Updates/Model/*.swift \
                           Nanocast/Features/Updates/Service/UpdateCheckStore.swift \
                           Nanocast/Platform/AppPaths.swift

if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    node -e '
const fs = require("node:fs");
const [comp, db] = process.argv.slice(1);
const existing = JSON.parse(fs.readFileSync(comp, "utf8"));
const harnesses = JSON.parse(fs.readFileSync(db, "utf8"));
const kept = existing.filter((e) => !(e.files || []).some((f) => f.includes("/Tests/")));
fs.writeFileSync(comp, JSON.stringify([...kept, ...harnesses], null, 1));
console.log(harnesses.length + " harness entries indexed into .compile");
' .compile "$DB"
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

JOBS="${NANOCAST_TEST_JOBS:-4}"
export NANOCAST_TEST_TIMEOUT="${NANOCAST_TEST_TIMEOUT:-300}"
started=$SECONDS

report() {
    local finished=0 line asked running file
    while :; do
        asked=$SECONDS
        if IFS= read -r -t 15 line; then
            case "$line" in "dispatch "*) return "${line#dispatch }";; esac
            finished=$((finished + 1))
            printf '[%*d/%d] %s\n' "${#ran}" "$finished" "$ran" "$line"
            continue
        fi
        # Bash 3.2 returns the same status for a timeout and EOF; only EOF comes back at once.
        if [ $((SECONDS - asked)) -lt 10 ]; then return 1; fi
        running=""
        for file in "$BIN"/*.running; do
            [ -e "$file" ] && running="$running $(basename "$file" .running)"
        done
        printf '        \033[2mstill running after %ds:%s\033[0m\n' $((SECONDS - started)) "$running"
    done
}

if ! { sort -s -k1,1n "$QUEUE" | cut -d' ' -f2- | xargs -P "$JOBS" -L1 "$SELF" --exec; echo "dispatch $?"; } | report; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi
elapsed=$((SECONDS - started))

# A compiler diagnostic is far longer than PIPE_BUF, so the workers log it and it is replayed here.
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < "$QUEUE"

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n\033[31mFAILED\033[0m  %d of %d harness(es) failed in %ds: %s\n' \
        "${#failed[@]}" "$ran" "$elapsed" "${failed[*]}" >&2
    exit 1
fi
printf '\n\033[32mPASSED\033[0m  All %d harness(es) passed in %ds.\n' "$ran" "$elapsed"
