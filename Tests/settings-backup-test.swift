import Foundation

@main
struct SettingsBackupTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        func naming(_ rule: String, _ offenders: [String]) -> String {
            offenders.isEmpty ? rule : "\(rule) — \(offenders.sorted().joined(separator: ", "))"
        }

        let persistedKeys: Set<String> = [
            "clipboardEnabled", "clipboardTextSearchEnabled", "clipboardRetentionDays",
            "clipboardDefaultAction", "clipboardDisabledApps", "hyperKeyPhysicalKey",
            "hyperKeyIncludesShift", "hyperKeyQuickPress", "hyperKeySecureInputCompatibility",
            "emojiSkinTone", "emojiGridColumns", "showInMenuBar", "automaticallyCheckForUpdates",
            "popToRootTimeout", "escapeKeyBehavior", "appearance", "calculatorNumberStyle",
            "interfaceSize", "compactMode", "showFavoritesInCompactMode", "launcherSearchScopes",
            "launcherShowsSuggestions", "rootSearchSensitivity", "openOnCursorScreen",
            "autoSwitchInputSource", "paletteDraggable", "palettePosition",
            "animationsEnabled", "dictationPlaysSounds",
            "paletteExpandedCenterDisplays", "fileSearchEnabled", "fileSearchScopes",
            "fileSearchIgnorePatterns", "fileSearchRemovedDefaultPatterns", "fileSearchShowInLauncher",
            "notesEnabled", "notesRendersMarkdown",
            "notesShowsFormattingBar", "notesFolder", "customCommandsEnabled",
            "customCommandsShowInLauncher", "screenshotSaveFolder", "navigationEnabled", "menuSearchDisabledApps",
            "menuSearchShowsAppleMenu", "windowSwitcherExcludedApps", "windowManagementEnabled",
            "windowManagementShowInLauncher",
            "windowManagementGap", "windowManagementCycleMode", "windowLayoutsShowInLauncher",
            "windowRoomsShowInLauncher", "dictationEnabled", "dictationMode", "dictationModel",
            "dictationMicrophone", "dictationDestination", "dictationAdaptsCapitalization",
            "dictationLiveInsertion", "dictationIdleReleaseMinutes", "dictationLanguage",
            "settingsFileEnabled"
        ]
        check(
            "every AppSettingsKey raw value is a persisted spelling, so a case rename cannot move one",
            Set(AppSettingsKey.allCases.map(\.rawValue)) == persistedKeys)

        let mirrored = SettingsBackupCoverage.mirrored
        let excluded = SettingsBackupCoverage.deliberatelyExcluded
        let external = SettingsBackupCoverage.externallySourced
        let allKeys = AppSettingsKey.allCases.map(\.rawValue)
        let mirroredKeys = mirrored.values.map(\.rawValue)

        let uncovered = allKeys.filter { !mirroredKeys.contains($0) && excluded[$0] == nil }
        check(
            naming("every AppSettings key is backed up or deliberately excluded", uncovered),
            uncovered.isEmpty)

        let bothWays = mirroredKeys.filter { excluded[$0] != nil }
        check(naming("no key is both backed up and excluded", bothWays), bothWays.isEmpty)

        let unknownExclusions = excluded.keys.filter { AppSettingsKey(rawValue: $0) == nil }
        check(
            naming("every excluded key names a real AppSettings key", Array(unknownExclusions)),
            unknownExclusions.isEmpty)

        let doubleClaimed = Dictionary(grouping: mirroredKeys, by: { $0 })
            .filter { $0.value.count > 1 }.keys
        check(
            naming("no two backup fields claim the same key", Array(doubleClaimed)),
            doubleClaimed.isEmpty)
        check(
            "fileSearchEnabled rides the settings backup",
            mirrored["fileSearchEnabled"] == .fileSearchEnabled)
        check(
            "file search scopes ride the settings backup",
            mirrored["fileSearchScopes"] == .fileSearchScopes)
        check(
            "user ignore patterns ride the settings backup",
            mirrored["fileSearchIgnorePatterns"] == .fileSearchIgnorePatterns)
        check(
            "removed default ignore patterns ride the settings backup",
            mirrored["fileSearchRemovedDefaultPatterns"] == .fileSearchRemovedDefaultPatterns)
        check("notes enablement rides the settings backup", mirrored["notesEnabled"] == .notesEnabled)
        check(
            "Markdown rendering rides the settings backup",
            mirrored["notesRendersMarkdown"] == .notesRendersMarkdown)
        check(
            "the formatting bar rides the settings backup",
            mirrored["notesShowsFormattingBar"] == .notesShowsFormattingBar)
        check(
            "clipboard enablement rides the settings backup",
            mirrored["clipboardEnabled"] == .clipboardEnabled)
        check(
            "emoji grid density rides the settings backup",
            mirrored["emojiGridColumns"] == .emojiGridColumns)

        for key: AppSettingsKey in [
            .dictationEnabled, .clipboardTextSearchEnabled, .settingsFileEnabled
        ] {
            check(
                "\(key.rawValue) stays out of a backup",
                excluded[key.rawValue] != nil && mirrored.values.allSatisfy { $0 != key })
        }

        let emptyReasons = excluded.filter { key, reason in
            let trimmed = reason.trimmingCharacters(in: .whitespaces)
            return trimmed.count <= key.count || !trimmed.contains(" ")
        }.keys
        check(
            naming("every exclusion carries a real reason", Array(emptyReasons)),
            emptyReasons.isEmpty)

        let claimedTwice = external.keys.filter { mirrored[$0] != nil }
        check(
            naming("no field is both mirrored and externally sourced", Array(claimedTwice)),
            claimedTwice.isEmpty)

        let notActuallyExternal = external.keys.filter { AppSettingsKey(rawValue: $0) != nil }
        check(
            naming("externally sourced fields have no AppSettings key", Array(notActuallyExternal)),
            notActuallyExternal.isEmpty)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
