import Foundation

@MainActor
enum SettingsFileSchema {
    static func bindings(
        settings: AppSettings, shortcuts: HotKeySettingsFile, launcher: LauncherSettingsFile,
        windowManagement: WindowManagementSettingsFile
    ) -> [SettingsFileBinding] {
        SettingsFileKey.allCases.map { key in
            binding(
                for: key, settings: settings, shortcuts: shortcuts, launcher: launcher,
                windowManagement: windowManagement)
        }
    }

    private static func binding(
        for key: SettingsFileKey, settings: AppSettings, shortcuts: HotKeySettingsFile,
        launcher: LauncherSettingsFile, windowManagement: WindowManagementSettingsFile
    ) -> SettingsFileBinding {
        func bind<Root: AnyObject, Value: SettingsFileValue>(
            _ root: Root, _ path: ReferenceWritableKeyPath<Root, Value>,
            accept: @escaping (Value) -> Value? = { $0 }
        ) -> SettingsFileBinding {
            SettingsFileBinding(key, root, path, accept: accept)
        }

        switch key {
        case .launcherShortcut:
            return shortcuts.binding(
                for: key, action: .togglePalette, name: "App Launcher")
        case .showInMenuBar: return bind(settings, \.showInMenuBar)
        case .automaticallyCheckForUpdates: return bind(settings, \.automaticallyCheckForUpdates)
        case .popToRootTimeout: return bind(settings, \.popToRootTimeout)
        case .escapeKeyBehavior: return bind(settings, \.escapeKeyBehavior)
        case .autoSwitchInputSource: return bind(settings, \.autoSwitchInputSourceID)
        case .appearance: return bind(settings, \.appearance)
        case .animationsEnabled: return bind(settings, \.animationsEnabled)
        case .interfaceSize: return bind(settings, \.interfaceSize)
        case .compactMode: return bind(settings, \.compactMode)
        case .compactBarCommands:
            return bind(settings, \.compactBarCommands) {
                CommandID.validCompactBarCommands($0) ? $0 : nil
            }
        case .openOnCursorScreen: return bind(settings, \.openOnCursorScreen)
        case .paletteDraggable: return bind(settings, \.paletteDraggable)
        case .hyperKey: return bind(settings, \.hyperKey)
        case .hyperKeyIncludesShift: return bind(settings, \.hyperKeyIncludesShift)
        case .hyperKeyQuickPress: return bind(settings, \.hyperKeyQuickPress)
        case .hyperKeySecureInputCompatibility:
            return bind(settings, \.hyperKeySecureInputCompatibility)
        case .calcNumberStyle: return bind(settings, \.calcNumberStyle)
        case .launcherShowsSuggestions: return bind(settings, \.launcherShowsSuggestions)
        case .rootSearchSensitivity: return bind(settings, \.rootSearchSensitivity)
        case .applicationsEnabled: return launcher.kindBinding(for: key, kind: .application)
        case .searchScopes: return bind(settings, \.searchScopes) { SearchScopes.normalize($0) }
        case .applications: return launcher.appsBinding(for: key)
        case .systemSettingsEnabled: return launcher.kindBinding(for: key, kind: .systemSettings)
        case .systemSettings: return launcher.panesBinding(for: key)
        case .systemActionsEnabled: return launcher.kindBinding(for: key, kind: .systemAction)
        case .systemActions: return launcher.systemActionsBinding(for: key)
        case .builtInCommandsEnabled: return launcher.kindBinding(for: key, kind: .command)
        case .builtInCommands: return launcher.commandsBinding(for: key, owner: nil)
        case .customCommandsEnabled: return bind(settings, \.customCommandsEnabled)
        case .customCommandsShowInLauncher: return bind(settings, \.customCommandsShowInLauncher)
        case .fileSearchEnabled: return bind(settings, \.fileSearchEnabled)
        case .fileSearchScopes: return bind(settings, \.fileSearchScopes)
        case .fileSearchIgnorePatterns: return bind(settings, \.fileSearchIgnorePatterns)
        case .fileSearchRemovedDefaultPatterns:
            return bind(settings, \.fileSearchRemovedDefaultPatterns)
        case .fileSearchShowInLauncher: return bind(settings, \.fileSearchShowInLauncher)
        case .fileSearchCommands: return launcher.commandsBinding(for: key, owner: .fileSearch)
        case .notesEnabled: return bind(settings, \.notesEnabled)
        case .notesRendersMarkdown: return bind(settings, \.notesRendersMarkdown)
        case .notesShowsFormattingBar: return bind(settings, \.notesShowsFormattingBar)
        case .notesFolder: return bind(settings, \.notesFolder, accept: folder)
        case .notesCommands: return launcher.commandsBinding(for: key, owner: .notes)
        case .dictationMode: return bind(settings, \.dictationMode)
        case .dictationShortcut:
            return shortcuts.binding(for: key, action: .dictation, name: "Dictation")
        case .dictationPlaysSounds: return bind(settings, \.dictationPlaysSounds)
        case .dictationModel: return bind(settings, \.dictationModel)
        case .dictationMicrophone: return bind(settings, \.dictationMicrophone)
        case .dictationDestination: return bind(settings, \.dictationDestination)
        case .dictationAdaptsCapitalization: return bind(settings, \.dictationAdaptsCapitalization)
        case .dictationLiveInsertion: return bind(settings, \.dictationLiveInsertion)
        case .dictationIdleRelease: return bind(settings, \.dictationIdleRelease)
        case .dictationLanguage:
            return bind(settings, \.dictationLanguage) { language in
                guard let language else { return .some(nil) }
                return DictationLanguage(rawValue: language) == nil ? nil : .some(language)
            }
        case .navigationEnabled: return bind(settings, \.navigationEnabled)
        case .menuSearchShowsAppleMenu: return bind(settings, \.menuSearchShowsAppleMenu)
        case .menuSearchDisabledApps: return bind(settings, \.menuSearchDisabledApps)
        case .windowSwitcherShortcut:
            return shortcuts.binding(for: key, action: .windowSwitcher, name: "Window Switcher")
        case .windowSwitcherExcludedApps: return bind(settings, \.windowSwitcherExcludedApps)
        case .navigationCommands: return launcher.commandsBinding(for: key, owner: .navigation)
        case .windowManagementEnabled: return bind(settings, \.windowManagementEnabled)
        case .windowManagementShowInLauncher:
            return bind(settings, \.windowManagementShowInLauncher)
        case .windowGap:
            return bind(settings, \.windowGap) {
                WindowPlacementEngine.gapRange.contains($0) ? $0 : nil
            }
        case .windowCycle: return bind(settings, \.windowCycle)
        case .windowLayoutsShowInLauncher: return bind(settings, \.windowLayoutsShowInLauncher)
        case .windowRoomsShowInLauncher: return bind(settings, \.windowRoomsShowInLauncher)
        case .windowShortcuts: return windowManagement.commandShortcutsBinding(for: key)
        case .windowAliases: return windowManagement.commandAliasesBinding(for: key)
        case .customWindowSizes: return windowManagement.customSizesBinding(for: key)
        case .windowLayouts: return windowManagement.layoutsBinding(for: key)
        case .windowRooms: return windowManagement.roomsBinding(for: key)
        case .windowManagementCommands:
            return launcher.commandsBinding(for: key, owner: .windowManagement)
        case .clipboardEnabled: return bind(settings, \.clipboardEnabled)
        case .clipboardRetention: return bind(settings, \.clipboardRetention)
        case .clipboardDefaultAction: return bind(settings, \.clipboardDefaultAction)
        case .clipboardDisabledApps: return bind(settings, \.clipboardDisabledApps)
        case .clipboardCommands: return launcher.commandsBinding(for: key, owner: .clipboard)
        case .screenshotSaveFolder: return bind(settings, \.screenshotSaveFolder, accept: folder)
        case .screenshotCommands: return launcher.commandsBinding(for: key, owner: .screenshot)
        case .emojiSkinTone: return bind(settings, \.emojiSkinTone)
        case .emojiGridColumns: return bind(settings, \.emojiGridColumns)
        case .emojiCommands: return launcher.commandsBinding(for: key, owner: .emoji)
        }
    }

    private static func folder(_ path: String?) -> String?? {
        guard let path else { return .some(nil) }
        return AppPaths.isFolderPath(path) ? path : nil
    }
}

extension PopToRootTimeout: SettingsFileRawValue {}
extension EscapeKeyBehavior: SettingsFileRawValue {}
extension CommandID: SettingsFileRawValue {}
extension AppAppearance: SettingsFileRawValue {}
extension InterfaceSize: SettingsFileRawValue {}
extension HyperKeyPhysicalKey: SettingsFileRawValue {}
extension HyperKeyQuickPress: SettingsFileRawValue {}
extension CalcNumberStyle: SettingsFileRawValue {}
extension SearchSensitivity: SettingsFileRawValue {}
extension WindowCycle: SettingsFileRawValue {}
extension ClipboardDefaultAction: SettingsFileRawValue {}
extension EmojiSkinTone: SettingsFileRawValue {}
extension EmojiGridColumns: SettingsFileRawValue {}
extension DictationModel: SettingsFileRawValue {}
extension DictationMode: SettingsFileRawValue {}
extension DictationDestination: SettingsFileRawValue {}
extension DictationIdleRelease: SettingsFileRawValue {}

extension ClipboardRetention: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .sixMonths: 180
        case .year: 365
        case .forever: "forever"
        }
    }
}
