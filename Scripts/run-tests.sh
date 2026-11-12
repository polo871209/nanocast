#!/bin/bash
# The test suite: each harness compiles the shipped sources it guards. See docs/testing.md.

set -uo pipefail

# Absolute: the workers re-enter this script after the cd, where a relative $0 would not resolve.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/nanocast-harness"
mkdir -p "$BIN"

# `--exec` is the worker half: xargs re-enters here once per queued harness.
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
    if ! compiled=$( { time swiftc -swift-version 6 "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2>&1 ); then
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

failed=()
ran=0
only="${1:-}"

# `--index` feeds harness compile commands to .compile, as xcodebuild never compiles Tests/.
emit_db=0
DB="${TMPDIR:-/tmp}/nanocast-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

QUEUE="$BIN/queue"
# `--index` queues nothing, so it must never reset the state of a suite already running.
if [ "$emit_db" -eq 0 ]; then
    # Queue, logs and verdicts are shared by path, so a second suite in this $TMPDIR waits its turn.
    if [ -z "${NANOCAST_SUITE_LOCKED:-}" ]; then
        export NANOCAST_SUITE_LOCKED=1
        lockf -k -t 0 "$BIN/suite.lock" true 2>/dev/null || echo "Waiting for the suite already running…" >&2
        exec lockf -k "$BIN/suite.lock" "$SELF" "$@"
    fi
    : > "$QUEUE"
    rm -f "$BIN"/*.failed "$BIN"/*.running
fi

# `slow` dispatches in the first wave; `index` only claims editor flags for a hand-run harness.
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
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # Only `Tests/` files: `.compile` is last-wins, so a shipped source keeps the app's command.
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    # xargs splits the queue on whitespace, so no harness source path may contain a space.
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

L=Nanocast/Features/Launcher/Model
run slow -O FuzzTests      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift
FS=Nanocast/Features/FileSearch
FILE_INDEX="$FS/Service/FileIndex.swift $FS/Service/FileIndexSnapshot.swift $FS/Service/FileIndexCrawler.swift"
run FileSearchTests        $FS/Model/*.swift
run FileIndexTests         $FS/Model/*.swift $FILE_INDEX
run FileSearchSessionTests $FS/Model/*.swift $FS/Service/FileSearchSession.swift $FILE_INDEX
run MenuSearchTests        $L/SearchRelevance.swift \
                           Nanocast/Features/MenuSearch/Model/*.swift \
                           Nanocast/Features/MenuSearch/Service/*.swift
run WindowSwitchTests      $L/SearchRelevance.swift \
                           Nanocast/Features/WindowSwitcher/Model/*.swift
run index FileSearchPerformanceTests $FS/Model/*.swift $FILE_INDEX
run RankingTests           $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/LauncherRankingStore.swift
run ScopesTests            $L/SearchScopes.swift
run AppNameTests           Nanocast/Platform/AppDisplayName.swift \
                           Nanocast/Platform/BundleLocalization.swift \
                           $L/SearchRelevance.swift
run FavoritesTests         $L/FavoriteSlots.swift
run AppInstallationTests   $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift $L/SearchScopes.swift \
                           Nanocast/Features/Launcher/Service/AppIndex.swift \
                           Nanocast/Features/Launcher/Service/AppLauncher.swift \
                           Nanocast/Features/Launcher/Service/RunningAppsMonitor.swift \
                           Nanocast/Features/Launcher/Service/FavoritesStore.swift \
                           $FS/Model/FileSearchResult.swift \
                           Nanocast/Features/Launcher/Service/AliasStore.swift \
                           Nanocast/Features/Launcher/Service/VisibilityStore.swift \
                           Nanocast/Features/Launcher/Service/BundleNameCache.swift \
                           Nanocast/Platform/AppDisplayName.swift Nanocast/Platform/BundleLocalization.swift \
                           Nanocast/Platform/SystemLanguages.swift \
                           Nanocast/Platform/Images/FileIconStamp.swift Nanocast/Platform/Memo.swift \
                           Nanocast/Platform/Signposts.swift Nanocast/Platform/NotificationToken.swift \
                           Nanocast/Platform/LocalizedResource.swift
run LauncherFileTests      $L/LauncherFileFormat.swift \
                           Nanocast/Features/Settings/Model/SettingsFileJSON.swift
run LauncherSettingsFileTests \
                           $L/LauncherFileFormat.swift $L/CommandID.swift $L/CommandCatalog.swift \
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
                           Nanocast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/SystemActions/Model/SystemAction.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/Snippets/Model/Snippet.swift \
                           Nanocast/Platform/LocalizedResource.swift
run AppleShortcutTests     Nanocast/Features/AppleShortcuts/Model/*.swift
run CalcTests              Nanocast/Features/Calculator/Model/*.swift
run index CalcPerformanceTests Nanocast/Features/Calculator/Model/*.swift
run CalendarTests          Nanocast/Features/Calendar/Model/*.swift \
                           Nanocast/Features/Calendar/UI/EventEditorSession.swift
run ClipboardTests         Nanocast/Features/Clipboard/Model/ClipboardStore.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorFormat.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift
run ClipboardCoordinatorTests Nanocast/Features/Clipboard/UI/ClipboardCoordinator.swift \
                           Nanocast/Features/Clipboard/Model/*.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Palette/PaletteState.swift Nanocast/Palette/PaletteMode.swift \
                           Nanocast/Palette/HoverArming.swift \
                           Nanocast/Features/Emoji/Model/EmojiCatalog.swift \
                           Nanocast/Features/FileSearch/Model/FileSearchFilter.swift \
                           Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift
run ClipboardThumbnailTests Nanocast/Features/Clipboard/Model/ClipboardStore.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorFormat.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift \
                           Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Platform/Images/ImageThumbnail.swift \
                           Nanocast/Platform/Images/ThumbnailCache.swift
# `Q` is the URL detector a drag payload builds its link with, rather than a second one.
Q=Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift
run ClipboardSearchTests   Nanocast/Features/Clipboard/Model/*.swift Nanocast/Platform/Images/ImageDerivative.swift $Q
run PasteSequenceTests     Nanocast/Features/Clipboard/Model/*.swift Nanocast/Platform/Images/ImageDerivative.swift $Q
run ClipboardTextTests     Nanocast/Features/Clipboard/Model/*.swift Nanocast/Platform/Images/ImageDerivative.swift $Q \
                           Nanocast/Features/Clipboard/Service/ClipboardTextExtractor.swift \
                           Nanocast/Features/Clipboard/Service/ClipboardTextIndexer.swift \
                           Nanocast/Features/Clipboard/Service/ClipboardTextWorker.swift \
                           Nanocast/Platform/ProcessExit.swift
run PasteboardTests        Nanocast/Platform/PasteboardFiles.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardStore.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorFormat.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift \
                           Nanocast/Features/Clipboard/Service/ClipboardManager.swift \
                           Nanocast/Features/Clipboard/Service/Paster.swift
run index ClipboardFilePerformanceTests \
                           Nanocast/Platform/PasteboardFiles.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardStore.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Nanocast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorFormat.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift \
                           Nanocast/Features/Clipboard/Service/ClipboardManager.swift
run index ClipboardThumbnailPerformanceTests \
                           Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Platform/Images/ImageThumbnail.swift \
                           Nanocast/Platform/Images/ImageDerivative.swift \
                           Nanocast/Platform/Images/ThumbnailCache.swift
run EmojiTests             Nanocast/Features/Emoji/Model/EmojiCatalog.swift \
                           Nanocast/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Nanocast/Features/Emoji/Model/EmojiData.generated.swift
run EmojiSearchTests       Nanocast/Features/Emoji/Model/EmojiCatalog.swift \
                           Nanocast/Features/Emoji/Model/EmojiData.generated.swift \
                           Nanocast/Features/Emoji/Service/EmojiIndex.swift \
                           Nanocast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Nanocast/Features/Emoji/Service/PinnedEmojiStore.swift \
                           Nanocast/Features/Launcher/Model/SearchRelevance.swift \
                           Nanocast/Platform/AppPaths.swift Nanocast/Platform/Memo.swift
run index EmojiSearchPerformanceTests \
                           Nanocast/Features/Emoji/Model/EmojiCatalog.swift \
                           Nanocast/Features/Emoji/Model/EmojiData.generated.swift \
                           Nanocast/Features/Emoji/Service/EmojiIndex.swift \
                           Nanocast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Nanocast/Features/Launcher/Model/SearchRelevance.swift \
                           Nanocast/Platform/AppPaths.swift Nanocast/Platform/Memo.swift
run PaletteSelectionTests  Nanocast/Features/PaletteRowIndex.swift \
                           Nanocast/Features/Emoji/Model/EmojiGridGeometry.swift
run AppearanceTests        Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Features/Settings/AppAppearance.swift
run LanguageTests          Nanocast/Features/Settings/AppLanguage.swift
run LocalizedResourceTests Nanocast/Platform/LocalizedResource.swift
run RelaunchTests          Nanocast/App/AppDelegate.swift Nanocast/Platform/RelaunchRunner.swift
run InterfaceSizeTests     Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Features/Settings/InterfaceSize.swift \
                           Nanocast/Features/Extensions/Model/ExtensionFormMetrics.swift
run PalettePlacementTests  Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Features/Settings/InterfaceSize.swift \
                           Nanocast/Palette/PalettePlacement.swift
run PaletteMenuClickTests  Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/Platform/WindowLevel.swift \
                           Nanocast/Platform/NotificationToken.swift \
                           Nanocast/DesignSystem/Interaction/KeyboardFocus.swift \
                           Nanocast/DesignSystem/Interaction/Motion.swift \
                           Nanocast/DesignSystem/Interaction/AnimatedPanel.swift \
                           Nanocast/Palette/PalettePanel.swift
run FormInputTests         Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/DesignSystem/FormTextInput.swift \
                           Nanocast/DesignSystem/FormTextArea.swift
run ScrollRevealTests      Nanocast/DesignSystem/Scrolling/SelectionReveal.swift
run RedactionTests         Nanocast/DesignSystem/RedactedPlaceholder.swift
run KeyboardFocusTests     Nanocast/DesignSystem/Interaction/KeyboardFocus.swift
run CommandEscapeTapTests  Nanocast/Palette/CommandEscapeTap.swift
run PaletteEscapeTests     Nanocast/Palette/PaletteMode.swift \
                           Nanocast/Palette/PaletteEscapeAction.swift \
                           Nanocast/Palette/CommandEscapeTap.swift \
                           Nanocast/Features/Settings/EscapeKeyBehavior.swift \
                           Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift
run PaletteNavigationTests Nanocast/Palette/PaletteState.swift \
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
                           Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift
run PaletteFilterTests     Nanocast/Palette/PaletteMode.swift \
                           Nanocast/Palette/PaletteFilterAction.swift \
                           Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift
run ActionMenuSearchTests  Nanocast/Palette/ActionMenuSearchQuery.swift \
                            Nanocast/Features/Launcher/Model/SearchRelevance.swift
run PaletteShortcutTests   Nanocast/Palette/PaletteShortcut.swift
run ASCIILayoutTests       Nanocast/Platform/ASCIIKeyboardLayout.swift
run PaletteTabTests        Nanocast/Palette/PaletteMode.swift \
                           Nanocast/Palette/PaletteTabAction.swift \
                           Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift
run CompactBarTests        Nanocast/Features/Launcher/Model/CompactBarSelection.swift \
                           Nanocast/Features/Settings/AppSettingsKey.swift \
                           Nanocast/Features/Settings/Model/*.swift \
                           Nanocast/Features/Launcher/Model/CommandID.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyAction.swift \
                           Nanocast/Features/QuickActions/Model/QuickAction.swift \
                           Nanocast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Nanocast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/SystemActions/Model/SystemAction.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/Snippets/Model/Snippet.swift \
                           Nanocast/Platform/LocalizedResource.swift
run FallbackTests          Nanocast/Features/Launcher/Model/Fallback.swift \
                           Nanocast/Features/Launcher/Model/CommandID.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyAction.swift \
                           Nanocast/Features/QuickActions/Model/QuickAction.swift \
                           Nanocast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Nanocast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/SystemActions/Model/SystemAction.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/Snippets/Model/Snippet.swift \
                           Nanocast/Platform/LocalizedResource.swift
run DictionaryTests        Nanocast/Features/Dictionary/Model/DictionaryEntry.swift \
                           Nanocast/Features/Dictionary/Model/DictionaryMarkup.swift
run DictationTests         Nanocast/Features/Dictation/Model/DictationModel.swift Nanocast/Features/Dictation/Model/DictationIdleRelease.swift Nanocast/Features/Dictation/Model/DictationLanguage.swift Nanocast/Features/Dictation/Model/DictationTextFormatter.swift
run DictationCueTests      Nanocast/Features/Dictation/Service/DictationCueRunner.swift
run DictationFieldTests    Nanocast/Features/Dictation/Model/DictationModel.swift \
                           Nanocast/Features/Dictation/Model/DictationAudioChunks.swift \
                           Nanocast/Features/Dictation/Model/DictationMode.swift \
                           Nanocast/Features/Dictation/Model/DictationDestination.swift \
                           Nanocast/Features/Dictation/Model/DictationTextFormatter.swift \
                           Nanocast/Features/Dictation/Service/DictationCoordinator.swift \
                           Nanocast/Features/Dictation/Service/DictationInsertionContext.swift \
                           Nanocast/Features/AI/UI/ChatComposerTextView.swift \
                           Nanocast/Features/TextInjection/Service/*.swift \
                           Nanocast/Features/Snippets/Model/*.swift \
                           Nanocast/Platform/AccessibilityText.swift \
                           Nanocast/Platform/PasteboardFiles.swift \
                           Nanocast/Platform/Appearance.swift Nanocast/DesignSystem/Theme.swift
run DictationVolumeTests   Nanocast/Features/Dictation/Model/DictationVolumeSnapshot.swift \
                           Nanocast/Features/Dictation/Service/DictationAudioDucker.swift \
                           Nanocast/Platform/AppPaths.swift
run index -O DictationPerformanceTests Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Features/Dictation/Model/DictationModel.swift \
                           Nanocast/Features/Dictation/Service/DictationWire.swift
run DictationInferenceTests Nanocast/Features/Dictation/Model/DictationAudioChunks.swift \
    Nanocast/Features/Dictation/Service/DictationSpectrum.swift \
    Nanocast/Features/Dictation/Helper/DictationTensor.swift Nanocast/Features/Dictation/Helper/DictationTokenizer.swift \
    Nanocast/Features/Dictation/Helper/DictationMel.swift
run DictationWorkerTests   Nanocast/Features/Dictation/Model/DictationModel.swift \
                           Nanocast/Features/Dictation/Model/DictationIdleRelease.swift \
                           Nanocast/Features/Dictation/Service/DictationWire.swift \
                           Nanocast/Features/Dictation/Service/DictationWorker.swift \
                           Nanocast/Features/Dictation/Service/DictationModelStore.swift \
                           Nanocast/Features/Dictation/Service/DictationModelDownloader.swift \
                           Nanocast/Platform/ProcessExit.swift Nanocast/Platform/AppPaths.swift
run HotKeyTests            Nanocast/Features/HotKeys/Model/DoubleTapModifier.swift \
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
                           Nanocast/Features/QuickActions/Model/QuickAction.swift \
                           Nanocast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Nanocast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Nanocast/Features/Launcher/Model/CommandID.swift \
                           Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/SystemActions/Model/SystemAction.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/Snippets/Model/Snippet.swift \
                           Nanocast/Platform/LocalizedResource.swift
run CalloutTests           Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Features/HotKeys/UI/CalloutPlacement.swift
run IconCacheTests         Nanocast/Platform/Appearance.swift \
                           Nanocast/Platform/Images/IconCache.swift
run EntryIconTests         Nanocast/Platform/Appearance.swift \
                           Nanocast/Platform/Images/IconCache.swift \
                           Nanocast/Platform/Images/FileIconStamp.swift
run ExtensionIconTests     Nanocast/Platform/Appearance.swift \
                           Nanocast/Platform/AppDisplayName.swift \
                           Nanocast/Platform/Images/IconCache.swift \
                           Nanocast/Platform/Compression/Zlib.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Features/Extensions/Model/ExtensionBootConfig.swift \
                           Nanocast/Features/Extensions/Model/ExtensionLaunchType.swift \
                           Nanocast/Features/Extensions/Model/ExtensionManifest.swift \
                           Nanocast/Features/Extensions/Model/ExtensionRefreshPolicy.swift \
                           Nanocast/Features/Extensions/Model/ExtensionRefreshState.swift \
                           Nanocast/Features/Extensions/Model/RenderNode.swift \
                           Nanocast/Features/Extensions/Service/ExtensionCatalog.swift \
                           Nanocast/Features/Extensions/Service/ExtensionFetcher.swift \
                           Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Features/Extensions/Service/ExtensionNodeShims.swift \
                           Nanocast/Features/Extensions/Service/ExtensionRuntime.swift \
                           Nanocast/Features/Extensions/Service/ExtensionIconCache.swift \
                           Nanocast/Features/Extensions/UI/ExtensionAnimatedImage.swift \
                           Nanocast/Features/Extensions/UI/ExtensionImage.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift
run SystemActionTests      Nanocast/Features/SystemActions/Model/SystemAction.swift \
                           Nanocast/Platform/LocalizedResource.swift
run MicrophoneMuteTests    Nanocast/Features/SystemActions/Service/SystemActionFailure.swift \
                           Nanocast/Features/SystemActions/Service/SystemActionRunner+Microphone.swift
run VolumeTests            Nanocast/Features/SystemActions/Model/VolumeLevel.swift
run WindowCommandTests     Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCycle.swift \
                           Nanocast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Nanocast/Features/WindowManagement/Model/WindowActionMemory.swift \
                           Nanocast/Platform/LocalizedResource.swift
run WindowPresetTests      Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/WindowManagement/Model/WindowShortcutPreset.swift \
                           Nanocast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Nanocast/Features/HotKeys/Model/ModifierKey.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Nanocast/Features/HotKeys/Model/HyperKey.swift \
                           Nanocast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Nanocast/Platform/ASCIIKeyboardLayout.swift \
                           Nanocast/Features/HotKeys/Service/KeyShortcut.swift \
                           Nanocast/Platform/LocalizedResource.swift
run SpaceGestureTests      Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/WindowManagement/Model/SpaceGesture.swift \
                           Nanocast/Platform/LocalizedResource.swift
run WindowLayoutTests      Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCycle.swift \
                           Nanocast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayout.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutStore.swift \
                           Nanocast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Nanocast/Features/WindowManagement/Model/CustomWindowSizeStore.swift \
                           Nanocast/Platform/LocalizedResource.swift
run DeepLinkTests          Nanocast/Features/DeepLinks/Model/DeepLink.swift \
                           Nanocast/Features/DeepLinks/Model/DeepLinkInput.swift \
                           Nanocast/Features/DeepLinks/Model/DeepLinkConsentPolicy.swift \
                           Nanocast/Features/DeepLinks/Model/DeepLinkSource.swift \
                           Nanocast/Features/DeepLinks/Model/CustomWindowSize+DeepLink.swift \
                           Nanocast/Features/Settings/SettingsTab.swift \
                           Nanocast/Features/Launcher/Model/CommandID.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyAction.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyAction+EntryID.swift \
                           Nanocast/Features/QuickActions/Model/QuickAction.swift \
                           Nanocast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Nanocast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/SystemActions/Model/SystemAction.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift \
                           Nanocast/Features/AppleShortcuts/Model/AppleShortcut.swift \
                           Nanocast/Features/Snippets/Model/Snippet.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
                           Nanocast/Features/WindowManagement/Model/WindowCycle.swift \
                           Nanocast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayout.swift \
                           Nanocast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Nanocast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Nanocast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Nanocast/Features/WindowManagement/Model/RoomGrid.swift \
                           Nanocast/Features/WindowManagement/Model/RoomWindow.swift \
                           Nanocast/Features/WindowManagement/Model/Room.swift \
                           Nanocast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Nanocast/Platform/LocalizedResource.swift
run WindowRoomTests        Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
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
                           Nanocast/Features/WindowManagement/Model/RoomParkingLedger.swift \
                           Nanocast/Platform/LocalizedResource.swift
run WindowFileTests        Nanocast/Features/WindowManagement/Model/WindowCommand.swift \
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
                           Nanocast/Features/Settings/Model/SettingsFileIdentity.swift \
                           Nanocast/Platform/LocalizedResource.swift
run CustomCommandTests     Nanocast/Platform/PseudoTerminal.swift \
                           Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Features/CustomCommands/Model/CustomCommand.swift \
                           Nanocast/Features/CustomCommands/Model/RaycastScriptImport.swift \
                           Nanocast/Features/CustomCommands/UI/CustomCommandEditorSession.swift \
                           Nanocast/Features/CustomCommands/Service/ShellCommandRunner.swift
run CustomCommandListTests Nanocast/Features/CustomCommands/Model/CustomCommand.swift \
                             Nanocast/Features/CustomCommands/UI/CustomCommandListScreen.swift
run UninstallCoordinatorTests Nanocast/Features/Uninstall/Model/*.swift \
                           Nanocast/Features/Uninstall/UI/UninstallCoordinator.swift
run UninstallTests         Nanocast/Features/Uninstall/Model/UninstallTarget.swift \
                           Nanocast/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Nanocast/Features/Uninstall/Model/UninstallRules.swift \
                           Nanocast/Features/Uninstall/Model/UninstallProtection.swift \
                           Nanocast/Features/Uninstall/Model/UninstallPlan.swift
run QuicklinkTests         Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Nanocast/Features/Quicklinks/Model/RaycastQuicklinkImport.swift \
                           Nanocast/Features/Quicklinks/UI/QuicklinkEditorSession.swift
run QuicklinkCoordinatorTests Nanocast/Features/Quicklinks/Model/Quicklink.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Nanocast/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Nanocast/Features/Quicklinks/UI/QuicklinkCoordinator.swift \
                           Nanocast/Features/Quicklinks/UI/QuicklinkEditorSession.swift \
                           Nanocast/Features/Quicklinks/UI/QuicklinkArgumentsAccessory.swift \
                           Nanocast/Features/Snippets/Model/Snippet.swift \
                           Nanocast/Features/Snippets/Model/SnippetTemplateEngine.swift
run slow SnippetsTests     Nanocast/Platform/NotificationToken.swift \
                           Nanocast/Platform/HealthTicker.swift \
                           Nanocast/Platform/AccessibilityText.swift \
                           Nanocast/Features/Snippets/Model/*.swift \
                           Nanocast/Features/Snippets/Service/*.swift \
                           Nanocast/Features/Snippets/UI/SnippetEditorSession.swift \
                           Nanocast/Features/TextInjection/Service/*.swift
run NotesTests             Nanocast/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Nanocast/Features/Notes/Model/*.swift \
                           Nanocast/Features/Notes/Service/*.swift
run NotesEditorTests       Nanocast/Platform/Signposts.swift \
                           Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Platform/NotificationToken.swift \
                           Nanocast/Features/TextInjection/Service/InjectableTextView.swift \
                           Nanocast/Features/Notes/Model/NoteDocument.swift \
                           Nanocast/Features/Notes/Model/NoteTitle.swift \
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
run -O index NotesEditorPerformanceTests \
                           Nanocast/Platform/Signposts.swift \
                           Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Platform/NotificationToken.swift \
                           Nanocast/Features/TextInjection/Service/InjectableTextView.swift \
                           Nanocast/Features/Notes/Model/NoteDocument.swift \
                           Nanocast/Features/Notes/Model/NoteTitle.swift \
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
run slow -O RaycastTests   Nanocast/Features/Backup/Model/RaycastImportError.swift \
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
run SettingsBackupTests    Nanocast/Features/Settings/AppSettingsKey.swift \
                           Nanocast/Features/Backup/Model/SettingsBackupCoverage.swift
run HyperKeyEngineTests    Nanocast/Features/HotKeys/Model/HyperKeyEngine.swift \
                           Nanocast/Features/HotKeys/Model/HyperKey.swift \
                           Nanocast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Nanocast/Features/HotKeys/Model/ModifierKey.swift \
                           Nanocast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Nanocast/Features/HotKeys/Service/KeyShortcut.swift \
                           Nanocast/Platform/ASCIIKeyboardLayout.swift
run HyperKeyTests          Nanocast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Nanocast/Features/HotKeys/Model/HyperKeyConflictPolicy.swift \
                           Nanocast/Features/HotKeys/Service/KeyboardRemapper.swift \
                           Nanocast/Features/HotKeys/Service/RemapInstanceLock.swift \
                           Tests/HyperKeyFixtures.swift
run DictationKeyTests      Nanocast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Nanocast/Features/HotKeys/Model/HyperKeyConflictPolicy.swift \
                           Nanocast/Features/HotKeys/Service/KeyboardRemapper.swift \
                           Nanocast/Features/HotKeys/Service/RemapInstanceLock.swift \
                           Nanocast/Features/HotKeys/Service/DictationKeyManager.swift \
                           Nanocast/Platform/HealthTicker.swift \
                           Nanocast/Platform/NotificationToken.swift \
                           Tests/HyperKeyFixtures.swift \
                           Tests/DictationKeyFixtures.swift
run HotKeyDispatchTests    Nanocast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Nanocast/Features/HotKeys/Model/ModifierKey.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Nanocast/Features/HotKeys/Model/HyperKey.swift \
                           Nanocast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Nanocast/Features/HotKeys/Model/HotKeyAction.swift \
                           Nanocast/Features/HotKeys/Service/KeyShortcut.swift \
                           Nanocast/Features/HotKeys/Service/HotKeyManager.swift \
                           Nanocast/Platform/ASCIIKeyboardLayout.swift \
                           Tests/HotKeyDispatchFixtures.swift
run SettingsFileTests      Nanocast/Features/Settings/Model/*.swift \
                           Nanocast/Features/Settings/Service/SettingsFileMonitor.swift \
                           Nanocast/Features/Settings/Service/SettingsFileRepository.swift \
                           Nanocast/Platform/AppPaths.swift
run BackupArchiveTests     Nanocast/Platform/AppPaths.swift \
                           Nanocast/Features/Backup/Model/BackupArchive.swift \
                           Nanocast/Features/Backup/Model/BackupBundle.swift \
                           Nanocast/Features/Backup/Model/BackupCategory.swift \
                           Nanocast/Features/Backup/Model/BackupClipboardItem.swift \
                           Nanocast/Features/Backup/Model/BackupManifest.swift \
                           Nanocast/Features/Backup/Service/BackupStaging.swift
E=Nanocast/Features/Extensions
run SymbolsTests           $E/Service/SymbolCatalog.swift
run ExtensionCleanupTests  $E/Service/ExtensionCleanup.swift \
                           $E/Service/ExtensionCatalog.swift \
                           Nanocast/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ExtensionRefreshTests  $E/Model/ExtensionManifest.swift \
                           Nanocast/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ExtensionMetadataTests $E/Model/ExtensionCommandMetadata.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift
run ExtensionVersionTests  $E/Model/ExtensionListing.swift \
                           $E/Service/ExtensionVersionStore.swift
run ExtensionStoreTests    $E/Model/ExtensionGitHubSource.swift \
                           $E/Model/ExtensionListing.swift \
                           $E/Model/ExtensionPackageManager.swift \
                           $E/Model/ExtensionStoreResponse.swift
run ExtensionFormTests     $E/Model/ExtensionFormMetrics.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/UI/ExtensionFormKey.swift \
                           $E/Model/ExtensionDateExpression.swift \
                           $E/UI/ExtensionListKey.swift \
                           Tests/ExtensionListKeyTests.swift
run ExtensionImageSizeTests $E/Model/ExtensionImageSize.swift
run ExtensionSignInTests   $E/Service/ExtensionSignInSession.swift
run ExtensionAccessoryTests $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionStorage.swift
run slow ExtensionTests    -parse-as-library \
                           Tests/ExtensionTests+MenuBar.swift \
                           Tests/ExtensionFetchTests.swift \
                           $E/Model/ExtensionLaunchError.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionStorage.swift \
                           $E/Service/ExtensionMenuBarManager.swift \
                           $E/Model/ExtensionCommandMetadata.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift \
                           $E/UI/ExtensionMenuBarController.swift \
                           $E/UI/ExtensionMenuBarImage.swift \
                           Nanocast/Platform/Appearance.swift \
                           Nanocast/Platform/AppDisplayName.swift \
                           Nanocast/Platform/Images/IconCache.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           $E/Model/ExtensionBootConfig.swift \
                           $E/Model/ExtensionDeepLink.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/Model/ExtensionGridLayout.swift \
                           $E/Model/ExtensionSearchState.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift \
                           $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Service/ExtensionFetcher.swift \
                           Nanocast/Platform/ProcessExit.swift \
                           $E/Service/ExtensionIconCache.swift \
                           $E/Service/ExtensionNodeShims.swift \
                           $E/Service/ExtensionRuntime.swift \
                           $E/Service/ExtensionNameResolver.swift \
                           $E/Service/ExtensionWebSocketBridge.swift \
                           $E/UI/ExtensionAnimatedImage.swift \
                           $E/UI/ExtensionImage.swift \
                           $E/UI/ExtensionScreen.swift \
                           $L/SearchRelevance.swift \
                           Nanocast/Platform/Compression/Zlib.swift \
                           Nanocast/Features/Clipboard/Model/ColorValue.swift \
                           Nanocast/Features/Clipboard/Model/ColorSpaces.swift
run SettingsHistoryTests   Nanocast/Features/Settings/SettingsTab.swift \
                           Nanocast/Features/Settings/SettingsHistory.swift \
                           Nanocast/Features/Settings/SettingsAnchor.swift \
                           Nanocast/Features/Settings/SettingsNavigationState.swift \
                           Nanocast/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift \
                           Nanocast/Platform/LocalizedResource.swift
run UpdatesTests           Nanocast/Features/Updates/Model/*.swift \
                           Nanocast/Features/Updates/Service/BundleSignature.swift \
                           Nanocast/Features/Updates/Service/UpdateSignature.swift
run UpdateCheckTests       Nanocast/Features/Updates/Model/*.swift \
                           Nanocast/Features/Updates/Service/UpdateCheckStore.swift \
                           Nanocast/Platform/AppPaths.swift
run SupportTests           Nanocast/Features/Support/Model/*.swift
run AIProviderTests        Nanocast/Features/Settings/AppSettingsKey.swift \
                           Nanocast/Features/AI/Model/*.swift \
                           Nanocast/Features/AI/Settings/AISettingsStore.swift \
                           Nanocast/Features/AI/Service/CodexAppServerClient.swift \
                           Nanocast/Features/AI/Service/InstalledAIProbe.swift \
                           Nanocast/Platform/ExecutableLocator.swift Nanocast/Platform/ProcessExit.swift
run OpenCodeMCPTests       Nanocast/Features/AI/Model/*.swift \
                           Nanocast/Platform/ExecutableLocator.swift Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Features/AI/Service/AIProvider.swift \
                           Nanocast/Features/AI/Service/AIToolLoopProvider.swift \
                           Nanocast/Features/AI/Service/InstalledCLIProvider.swift \
                           Nanocast/Features/AI/Service/OpenCodeMCPBridge.swift
run AIChatTests            Nanocast/Features/AI/Model/AIRequest.swift \
                           Nanocast/Features/AI/Model/AIConnection.swift \
                           Nanocast/Features/AI/Model/AIConversationOpenPolicy.swift \
                           Nanocast/Features/AI/Model/AppleIntelligence.swift \
                           Nanocast/Features/AI/Model/AIAttachmentPolicy.swift \
                           Nanocast/Features/AI/Model/AIRetention.swift \
                           Nanocast/Features/AI/Model/AITool.swift \
                           Nanocast/Features/AI/Model/JSONValue.swift \
                           Nanocast/Features/AI/Model/ChatMessage.swift \
                           Nanocast/Features/AI/Model/ChatSession.swift \
                           Nanocast/Features/AI/Model/ChatPreset.swift \
                           Nanocast/Features/AI/Model/ChatChoices.swift \
                           Nanocast/Features/AI/Model/ChatReferences.swift \
                           Nanocast/Features/AI/Model/ChatTitle.swift \
                           Nanocast/Features/AI/Model/ChatFind.swift \
                           Nanocast/Features/AI/Model/ChatCitations.swift \
                           Nanocast/Features/AI/Model/ChatToolScope.swift \
                           Nanocast/Features/AI/Model/MarkdownBlock.swift \
                           Nanocast/Features/AI/Model/MarkdownMath.swift \
                           Nanocast/Features/AI/Model/MathFormula.swift \
                           Nanocast/Features/AI/Model/MathNode.swift \
                           Nanocast/Features/AI/Model/MathSymbolCatalog.swift \
                           Nanocast/Features/AI/Service/AIProvider.swift \
                           Nanocast/Features/AI/Service/ChatHistoryStore.swift \
                           Nanocast/Features/AI/Service/AIToolLoopProvider.swift \
                           Nanocast/Features/AI/UI/AIChatState.swift \
                           Nanocast/Features/AI/UI/AIChatSurfacesState.swift \
                           Nanocast/Features/AI/UI/ChatFindState.swift
run AIResponsesTests       Nanocast/Features/AI/Model/AIConnection.swift \
                           Nanocast/Features/AI/Model/AppleIntelligence.swift \
                           Nanocast/Features/AI/Model/AIModelDiscovery.swift \
                           Nanocast/Features/AI/Model/AIRequest.swift \
                           Nanocast/Features/AI/Model/AIRequestBody.swift \
                           Nanocast/Features/AI/Model/AIStreamDecoder.swift \
                           Nanocast/Features/AI/Model/AIResponsesDecoder.swift \
                           Nanocast/Features/AI/Model/ChatReferences.swift \
                           Nanocast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Nanocast/Features/AI/Model/AIProviderFailure.swift \
                           Nanocast/Features/AI/Model/AITool.swift \
                           Nanocast/Features/AI/Model/JSONValue.swift \
                           Nanocast/Features/AI/Service/AIProvider.swift \
                           Nanocast/Features/AI/Service/AIToolLoopProvider.swift
run ChatMarkdownTests      Nanocast/Platform/Appearance.swift \
                           Nanocast/DesignSystem/Theme.swift \
                           Nanocast/DesignSystem/InterfaceMetrics.swift \
                           Nanocast/Features/Settings/InterfaceSize.swift \
                           Nanocast/Features/AI/Model/AIRequest.swift \
                           Nanocast/Features/AI/Model/AITool.swift \
                           Nanocast/Features/AI/Model/JSONValue.swift \
                           Nanocast/Features/AI/Model/ChatMessage.swift \
                           Nanocast/Features/AI/Model/ChatChoices.swift \
                           Nanocast/Features/AI/Model/ChatReferences.swift \
                           Nanocast/Features/AI/Model/ChatCitations.swift \
                           Nanocast/Features/AI/Model/ChatFind.swift \
                           Nanocast/Features/AI/Model/MarkdownBlock.swift \
                           Nanocast/Features/AI/Model/MarkdownMath.swift \
                           Nanocast/Features/AI/Model/MathFormula.swift \
                           Nanocast/Features/AI/Model/MathNode.swift \
                           Nanocast/Features/AI/Model/MathSymbolCatalog.swift \
                           Nanocast/Features/AI/Model/SyntaxGrammar.swift \
                           Nanocast/Features/AI/Model/SyntaxHighlighter.swift \
                           Nanocast/Features/AI/Model/SyntaxStructuredLexers.swift \
                           Nanocast/Features/AI/UI/ChatTextHighlight.swift \
                           Nanocast/Features/AI/UI/ChatMarkdownRenderer.swift \
                           Nanocast/Features/AI/UI/MathAttachmentCell.swift \
                           Nanocast/Features/AI/UI/MathBox.swift \
                           Nanocast/Features/AI/UI/MathFont.swift \
                           Nanocast/Features/AI/UI/MathLayoutEngine.swift
run SyntaxHighlightTests   Nanocast/Features/AI/Model/SyntaxGrammar.swift \
                           Nanocast/Features/AI/Model/SyntaxHighlighter.swift \
                           Nanocast/Features/AI/Model/SyntaxStructuredLexers.swift
run MCPTests               Nanocast/Features/Settings/AppSettingsKey.swift \
                           Nanocast/Features/AI/Model/AIConnection.swift \
                           Nanocast/Features/AI/Model/AppleIntelligence.swift \
                           Nanocast/Features/AI/Model/AITool.swift \
                           Nanocast/Features/AI/Model/AIToolServer.swift \
                           Nanocast/Features/AI/Model/JSONValue.swift \
                           Nanocast/Features/MCP/Model/*.swift \
                           Nanocast/Features/MCP/Settings/MCPSettingsStore.swift
run -O TextDiffTests       Nanocast/Features/QuickActions/Model/TextDiffEngine.swift
run index TextDiffPerformanceTests Nanocast/Features/QuickActions/Model/TextDiffEngine.swift
run QuickActionTests       Nanocast/Features/Settings/AppSettingsKey.swift \
                           Nanocast/Features/AI/Model/AIConnection.swift \
                           Nanocast/Features/AI/Model/AppleIntelligence.swift \
                           Nanocast/Features/AI/Model/ChatGPTSubscription.swift \
                           Nanocast/Features/AI/Model/InstalledAI.swift \
                           Nanocast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Nanocast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Nanocast/Features/QuickActions/Model/CustomQuickActionStore.swift \
                           Nanocast/Features/QuickActions/Model/QuickAction.swift \
                           Nanocast/Features/QuickActions/Model/QuickActionFailure.swift \
                           Nanocast/Features/QuickActions/Model/QuickActionPrompt.swift \
                           Nanocast/Features/QuickActions/Model/QuickActionSettings.swift \
                           Nanocast/Features/QuickActions/Settings/QuickActionSettingsStore.swift \
                           Nanocast/Platform/LocalizedResource.swift
run AppleIntelligenceTests Nanocast/Features/Settings/AppSettingsKey.swift \
                           Nanocast/Features/AI/Model/*.swift \
                           Nanocast/Features/AI/Service/AIProvider.swift \
                           Nanocast/Features/AI/Service/AppleIntelligenceProvider.swift
run MCPOAuthTests          Nanocast/Platform/ExecutableLocator.swift \
                           Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Platform/KeychainSecretStore.swift \
                           Nanocast/Features/Settings/AppSettingsKey.swift \
                           Nanocast/Features/AI/Model/AIConnection.swift \
                           Nanocast/Features/AI/Model/AppleIntelligence.swift \
                           Nanocast/Features/AI/Model/AITool.swift \
                           Nanocast/Features/AI/Model/AIToolServer.swift \
                           Nanocast/Features/AI/Model/AIStreamDecoder.swift \
                           Nanocast/Features/AI/Model/AIResponsesDecoder.swift \
                           Nanocast/Features/AI/Model/ChatReferences.swift \
                           Nanocast/Features/AI/Model/AIProviderFailure.swift \
                           Nanocast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Nanocast/Features/AI/Model/AIRequest.swift \
                           Nanocast/Features/AI/Model/JSONValue.swift \
                           Nanocast/Features/MCP/Model/*.swift \
                           Nanocast/Features/MCP/Service/*.swift
run slow MCPStdioTests     Nanocast/Platform/ExecutableLocator.swift \
                           Nanocast/Platform/ProcessExit.swift \
                           Nanocast/Platform/KeychainSecretStore.swift \
                           Nanocast/Features/Settings/AppSettingsKey.swift \
                           Nanocast/Features/AI/Model/AIConnection.swift \
                           Nanocast/Features/AI/Model/AppleIntelligence.swift \
                           Nanocast/Features/AI/Model/AITool.swift \
                           Nanocast/Features/AI/Model/AIToolServer.swift \
                           Nanocast/Features/AI/Model/AIStreamDecoder.swift \
                           Nanocast/Features/AI/Model/AIResponsesDecoder.swift \
                           Nanocast/Features/AI/Model/ChatReferences.swift \
                           Nanocast/Features/AI/Model/AIProviderFailure.swift \
                           Nanocast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Nanocast/Features/AI/Model/AIRequest.swift \
                           Nanocast/Features/AI/Model/JSONValue.swift \
                           Nanocast/Features/MCP/Model/*.swift \
                           Nanocast/Features/MCP/Service/*.swift

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

# `sort -s` is stable, so the slow harnesses lead and everything else keeps its declaration order.
JOBS="${NANOCAST_TEST_JOBS:-4}"
export NANOCAST_TEST_TIMEOUT="${NANOCAST_TEST_TIMEOUT:-300}"
started=$SECONDS

# Numbers each result, and names what is still running whenever the output goes quiet.
report() {
    local finished=0 line asked running file
    while :; do
        asked=$SECONDS
        if IFS= read -r -t 15 line; then
            case "$line" in
                "dispatch "*)
                    [ "$finished" -eq "$ran" ] || return 1
                    return "${line#dispatch }";;
            esac
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

dispatch() {
    [ -s "$1" ] || return 0
    sort -s -k1,1n "$1" | cut -d' ' -f2- | xargs -P "$2" -L1 "$SELF" --exec
}

# Without this the suite reports "all passed" whenever dispatch itself dies and no harness ran.
if ! {
    dispatch "$QUEUE" "$JOBS"
    echo "dispatch $?"
} | report; then
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
