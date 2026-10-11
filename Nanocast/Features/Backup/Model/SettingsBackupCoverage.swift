import Foundation

enum SettingsBackupCoverage {
    static let mirrored: [String: AppSettingsKey] = [
        "clipboardEnabled": .clipboardEnabled,
        "clipboardRetentionDays": .clipboardRetention,
        "clipboardDefaultAction": .clipboardDefaultAction,
        "clipboardDisabledApps": .clipboardDisabledApps,
        "hyperKey": .hyperKey,
        "hyperKeyIncludesShift": .hyperKeyIncludesShift,
        "hyperKeyQuickPress": .hyperKeyQuickPress,
        "hyperKeySecureInputCompatibility": .hyperKeySecureInputCompatibility,
        "showInMenuBar": .showInMenuBar,
        "automaticallyCheckForUpdates": .automaticallyCheckForUpdates,
        "emojiSkinTone": .emojiSkinTone,
        "emojiGridColumns": .emojiGridColumns,
        "popToRootSeconds": .popToRootTimeout,
        "escapeKeyBehavior": .escapeKeyBehavior,
        "appearance": .appearance,
        "calcNumberStyle": .calcNumberStyle,
        "interfaceSize": .interfaceSize,
        "compactMode": .compactMode,
        "compactBarCommands": .compactBarCommands,
        "searchScopes": .searchScopes,
        "launcherShowsSuggestions": .launcherShowsSuggestions,
        "rootSearchSensitivity": .rootSearchSensitivity,
        "openOnCursorScreen": .openOnCursorScreen,
        "paletteDraggable": .paletteDraggable,
        "animationsEnabled": .animationsEnabled,
        "fileSearchEnabled": .fileSearchEnabled,
        "fileSearchScopes": .fileSearchScopes,
        "fileSearchIgnorePatterns": .fileSearchIgnorePatterns,
        "fileSearchRemovedDefaultPatterns": .fileSearchRemovedDefaultPatterns,
        "fileSearchShowInLauncher": .fileSearchShowInLauncher,
        "notesEnabled": .notesEnabled,
        "notesRendersMarkdown": .notesRendersMarkdown,
        "notesShowsFormattingBar": .notesShowsFormattingBar,
        "notesShowsInMenuBar": .notesShowsInMenuBar,
        "customCommandsEnabled": .customCommandsEnabled,
        "customCommandsShowInLauncher": .customCommandsShowInLauncher,
        "navigationEnabled": .navigationEnabled,
        "menuSearchDisabledApps": .menuSearchDisabledApps,
        "menuSearchShowsAppleMenu": .menuSearchShowsAppleMenu,
        "windowSwitcherExcludedApps": .windowSwitcherExcludedApps,
        "windowManagementEnabled": .windowManagementEnabled,
        "windowManagementShowInLauncher": .windowManagementShowInLauncher,
        "windowGap": .windowGap,
        "windowCycle": .windowCycle,
        "windowLayoutsShowInLauncher": .windowLayoutsShowInLauncher,
        "windowRoomsShowInLauncher": .windowRoomsShowInLauncher
    ]

    static let externallySourced: [String: String] = [
        "launchAtLogin": "Read from LaunchAtLogin, which owns the login item, not UserDefaults."
    ]

    static let deliberatelyExcluded: [String: String] = [
        AppSettingsKey.clipboardTextSearchEnabled.rawValue:
            "Background OCR is an opt-in processing choice on this Mac; a backup must not enable it.",
        AppSettingsKey.palettePosition.rawValue:
            "Machine-local geometry: every entry names a display this Mac has, and no other one.",
        AppSettingsKey.paletteExpandedCenterDisplays.rawValue:
            "Machine-local geometry: every entry names a display this Mac has, and no other one.",
        AppSettingsKey.autoSwitchInputSource.rawValue:
            "Names a keyboard input source installed on this Mac; another Mac may not have it.",
        AppSettingsKey.notesFolder.rawValue:
            "Names a folder on this Mac; the one a backup lands on may not have it.",
        AppSettingsKey.settingsFileEnabled.rawValue:
            "Lets a file on this Mac change its settings; an import must not hand that to another."
    ]
}
