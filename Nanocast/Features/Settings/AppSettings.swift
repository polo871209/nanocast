import SwiftUI

enum PopToRootTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterFive = 5
    case afterFifteen = 15
    case afterThirty = 30
    case afterSixty = 60
    case afterNinety = 90

    var id: Int { rawValue }

    var title: String {
        self == .immediately
            ? "Immediately" : rawValue == 1 ? "After 1 second" : "After \(rawValue) seconds"
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard
    private typealias Key = AppSettingsKey

    var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: Key.searchScopes.rawValue) }
    }

    var launcherShowsSuggestions: Bool {
        didSet {
            defaults.set(launcherShowsSuggestions, forKey: Key.launcherShowsSuggestions.rawValue)
        }
    }

    var rootSearchSensitivity: SearchSensitivity {
        didSet {
            defaults.set(rootSearchSensitivity.rawValue, forKey: Key.rootSearchSensitivity.rawValue)
        }
    }

    var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Key.clipboardEnabled.rawValue) }
    }

    var clipboardTextSearchEnabled: Bool {
        didSet { defaults.set(clipboardTextSearchEnabled, forKey: Key.clipboardTextSearchEnabled.rawValue) }
    }

    var clipboardRetention: ClipboardRetention {
        didSet {
            defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention.rawValue)
        }
    }

    var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps.rawValue) }
    }

    var clipboardDefaultAction: ClipboardDefaultAction {
        didSet {
            defaults.set(
                clipboardDefaultAction.rawValue, forKey: Key.clipboardDefaultAction.rawValue)
        }
    }

    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Key.showInMenuBar.rawValue) }
    }

    var automaticallyCheckForUpdates: Bool {
        didSet {
            defaults.set(
                automaticallyCheckForUpdates, forKey: Key.automaticallyCheckForUpdates.rawValue)
        }
    }

    var hyperKey: HyperKeyPhysicalKey {
        didSet { defaults.set(hyperKey.rawValue, forKey: Key.hyperKey.rawValue) }
    }

    var hyperKeyIncludesShift: Bool {
        didSet { defaults.set(hyperKeyIncludesShift, forKey: Key.hyperKeyIncludesShift.rawValue) }
    }

    var hyperKeyQuickPress: HyperKeyQuickPress {
        didSet {
            defaults.set(hyperKeyQuickPress.rawValue, forKey: Key.hyperKeyQuickPress.rawValue)
        }
    }

    var hyperKeySecureInputCompatibility: Bool {
        didSet {
            defaults.set(
                hyperKeySecureInputCompatibility,
                forKey: Key.hyperKeySecureInputCompatibility.rawValue)
        }
    }

    var emojiSkinTone: EmojiSkinTone {
        didSet { defaults.set(emojiSkinTone.rawValue, forKey: Key.emojiSkinTone.rawValue) }
    }

    var emojiGridColumns: EmojiGridColumns {
        didSet { defaults.set(emojiGridColumns.rawValue, forKey: Key.emojiGridColumns.rawValue) }
    }

    var popToRootTimeout: PopToRootTimeout {
        didSet { defaults.set(popToRootTimeout.rawValue, forKey: Key.popToRootTimeout.rawValue) }
    }

    var escapeKeyBehavior: EscapeKeyBehavior {
        didSet { defaults.set(escapeKeyBehavior.rawValue, forKey: Key.escapeKeyBehavior.rawValue) }
    }

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance.rawValue) }
    }

    var calcNumberStyle: CalcNumberStyle {
        didSet { defaults.set(calcNumberStyle.rawValue, forKey: Key.calcNumberStyle.rawValue) }
    }

    var interfaceSize: InterfaceSize {
        didSet {
            defaults.set(interfaceSize.rawValue, forKey: Key.interfaceSize.rawValue)
            let shift = Double(
                (oldValue.metrics.size.panelWidth - interfaceSize.metrics.size.panelWidth) / 2)
            if shift != 0 {
                palettePositions = palettePositions.mapValues { offset in
                    offset.count == 2 ? [offset[0] + shift, offset[1]] : offset
                }
            }
        }
    }

    var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: Key.compactMode.rawValue) }
    }

    var compactBarCommands: [CommandID] {
        didSet { defaults.set(compactBarCommands.map(\.rawValue), forKey: Key.compactBarCommands.rawValue) }
    }

    var openOnCursorScreen: Bool {
        didSet { defaults.set(openOnCursorScreen, forKey: Key.openOnCursorScreen.rawValue) }
    }

    var autoSwitchInputSourceID: String? {
        didSet {
            guard let autoSwitchInputSourceID else {
                defaults.removeObject(forKey: Key.autoSwitchInputSource.rawValue)
                return
            }
            defaults.set(autoSwitchInputSourceID, forKey: Key.autoSwitchInputSource.rawValue)
        }
    }

    var paletteDraggable: Bool {
        didSet { defaults.set(paletteDraggable, forKey: Key.paletteDraggable.rawValue) }
    }

    var animationsEnabled: Bool {
        didSet { defaults.set(animationsEnabled, forKey: Key.animationsEnabled.rawValue) }
    }

    var palettePositions: [String: [Double]] {
        didSet { defaults.set(palettePositions, forKey: Key.palettePosition.rawValue) }
    }

    var paletteExpandedCenterDisplays: Set<String> {
        didSet {
            defaults.set(
                Array(paletteExpandedCenterDisplays),
                forKey: Key.paletteExpandedCenterDisplays.rawValue)
        }
    }

    func palettePosition(on display: String) -> CGPoint? {
        palettePositions[display].flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }

    func setPalettePosition(_ offset: CGPoint?, on display: String, expandedCenter: Bool) {
        if offset != nil && expandedCenter {
            paletteExpandedCenterDisplays.insert(display)
        } else {
            paletteExpandedCenterDisplays.remove(display)
        }
        guard let offset else {
            palettePositions.removeValue(forKey: display)
            return
        }
        palettePositions[display] = [offset.x, offset.y]
    }

    var fileSearchEnabled: Bool {
        didSet { defaults.set(fileSearchEnabled, forKey: Key.fileSearchEnabled.rawValue) }
    }

    var fileSearchScopes: [String] {
        didSet { defaults.set(fileSearchScopes, forKey: Key.fileSearchScopes.rawValue) }
    }

    var fileSearchIgnorePatterns: [String] {
        didSet {
            defaults.set(fileSearchIgnorePatterns, forKey: Key.fileSearchIgnorePatterns.rawValue)
        }
    }

    var fileSearchRemovedDefaultPatterns: [String] {
        didSet {
            defaults.set(
                fileSearchRemovedDefaultPatterns,
                forKey: Key.fileSearchRemovedDefaultPatterns.rawValue)
        }
    }

    var fileSearchEffectiveIgnorePatterns: [String] {
        FileSearchIgnoreList.patterns(
            added: fileSearchIgnorePatterns, removedDefaults: fileSearchRemovedDefaultPatterns)
    }

    var fileSearchShowInLauncher: Bool {
        didSet {
            defaults.set(fileSearchShowInLauncher, forKey: Key.fileSearchShowInLauncher.rawValue)
        }
    }

    var notesEnabled: Bool {
        didSet { defaults.set(notesEnabled, forKey: Key.notesEnabled.rawValue) }
    }

    var dictationEnabled: Bool {
        didSet { defaults.set(dictationEnabled, forKey: Key.dictationEnabled.rawValue) }
    }

    var dictationMode: DictationMode {
        didSet { defaults.set(dictationMode.rawValue, forKey: Key.dictationMode.rawValue) }
    }

    var dictationModel: DictationModel {
        didSet { defaults.set(dictationModel.rawValue, forKey: Key.dictationModel.rawValue) }
    }

    var dictationMicrophone: String? {
        didSet { defaults.set(dictationMicrophone, forKey: Key.dictationMicrophone.rawValue) }
    }

    var dictationDestination: DictationDestination {
        didSet { defaults.set(dictationDestination.rawValue, forKey: Key.dictationDestination.rawValue) }
    }

    var dictationAdaptsCapitalization: Bool {
        didSet {
            defaults.set(dictationAdaptsCapitalization, forKey: Key.dictationAdaptsCapitalization.rawValue)
        }
    }

    /// Off by default: chunked transcription costs extra inference while recording.
    var dictationLiveInsertion: Bool {
        didSet { defaults.set(dictationLiveInsertion, forKey: Key.dictationLiveInsertion.rawValue) }
    }

    var dictationPlaysSounds: Bool {
        didSet { defaults.set(dictationPlaysSounds, forKey: Key.dictationPlaysSounds.rawValue) }
    }

    var dictationIdleRelease: DictationIdleRelease {
        didSet { defaults.set(dictationIdleRelease.rawValue, forKey: Key.dictationIdleRelease.rawValue) }
    }

    var dictationLanguage: String? {
        didSet { defaults.set(dictationLanguage, forKey: Key.dictationLanguage.rawValue) }
    }

    var notesRendersMarkdown: Bool {
        didSet { defaults.set(notesRendersMarkdown, forKey: Key.notesRendersMarkdown.rawValue) }
    }

    var notesShowsFormattingBar: Bool {
        didSet { defaults.set(notesShowsFormattingBar, forKey: Key.notesShowsFormattingBar.rawValue) }
    }

    var notesShowsInMenuBar: Bool {
        didSet { defaults.set(notesShowsInMenuBar, forKey: Key.notesShowsInMenuBar.rawValue) }
    }

    var notesFolder: String? {
        didSet { defaults.set(notesFolder, forKey: Key.notesFolder.rawValue) }
    }

    var customCommandsEnabled: Bool {
        didSet { defaults.set(customCommandsEnabled, forKey: Key.customCommandsEnabled.rawValue) }
    }

    var customCommandsShowInLauncher: Bool {
        didSet {
            defaults.set(
                customCommandsShowInLauncher, forKey: Key.customCommandsShowInLauncher.rawValue)
        }
    }

    var navigationEnabled: Bool {
        didSet { defaults.set(navigationEnabled, forKey: Key.navigationEnabled.rawValue) }
    }

    var menuSearchDisabledApps: [String] {
        didSet { defaults.set(menuSearchDisabledApps, forKey: Key.menuSearchDisabledApps.rawValue) }
    }

    var menuSearchShowsAppleMenu: Bool {
        didSet {
            defaults.set(menuSearchShowsAppleMenu, forKey: Key.menuSearchShowsAppleMenu.rawValue)
        }
    }

    var windowManagementEnabled: Bool {
        didSet {
            defaults.set(windowManagementEnabled, forKey: Key.windowManagementEnabled.rawValue)
        }
    }

    var windowManagementShowInLauncher: Bool {
        didSet {
            defaults.set(
                windowManagementShowInLauncher,
                forKey: Key.windowManagementShowInLauncher.rawValue)
        }
    }

    var windowGap: Int {
        didSet { defaults.set(windowGap, forKey: Key.windowGap.rawValue) }
    }

    var windowLayoutsShowInLauncher: Bool {
        didSet {
            defaults.set(
                windowLayoutsShowInLauncher, forKey: Key.windowLayoutsShowInLauncher.rawValue)
        }
    }

    var windowRoomsShowInLauncher: Bool {
        didSet {
            defaults.set(windowRoomsShowInLauncher, forKey: Key.windowRoomsShowInLauncher.rawValue)
        }
    }

    var windowCycle: WindowCycle {
        didSet { defaults.set(windowCycle.rawValue, forKey: Key.windowCycle.rawValue) }
    }

    var settingsFileEnabled: Bool {
        didSet { defaults.set(settingsFileEnabled, forKey: Key.settingsFileEnabled.rawValue) }
    }

    init() {
        clipboardEnabled =
            defaults.object(forKey: Key.clipboardEnabled.rawValue) == nil
            || defaults.bool(forKey: Key.clipboardEnabled.rawValue)
        clipboardTextSearchEnabled = defaults.bool(forKey: Key.clipboardTextSearchEnabled.rawValue)
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention.rawValue))
            ?? .threeMonths
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps.rawValue)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        clipboardDefaultAction =
            defaults.string(forKey: Key.clipboardDefaultAction.rawValue)
            .flatMap(ClipboardDefaultAction.init) ?? .paste
        launchAtLogin = LaunchAtLogin.isEnabled
        showInMenuBar =
            defaults.object(forKey: Key.showInMenuBar.rawValue) == nil
            || defaults.bool(forKey: Key.showInMenuBar.rawValue)
        automaticallyCheckForUpdates =
            defaults.object(forKey: Key.automaticallyCheckForUpdates.rawValue) == nil
            || defaults.bool(forKey: Key.automaticallyCheckForUpdates.rawValue)
        hyperKey =
            defaults.string(forKey: Key.hyperKey.rawValue).flatMap(HyperKeyPhysicalKey.init)
            ?? .none
        hyperKeyIncludesShift =
            defaults.object(forKey: Key.hyperKeyIncludesShift.rawValue) == nil
            || defaults.bool(forKey: Key.hyperKeyIncludesShift.rawValue)
        hyperKeyQuickPress =
            defaults.string(forKey: Key.hyperKeyQuickPress.rawValue)
            .flatMap(HyperKeyQuickPress.init)
            ?? .none
        hyperKeySecureInputCompatibility = defaults.bool(
            forKey: Key.hyperKeySecureInputCompatibility.rawValue)
        emojiSkinTone =
            defaults.string(forKey: Key.emojiSkinTone.rawValue).flatMap(EmojiSkinTone.init) ?? .none
        emojiGridColumns =
            EmojiGridColumns(rawValue: defaults.integer(forKey: Key.emojiGridColumns.rawValue))
            ?? .default
        popToRootTimeout =
            PopToRootTimeout(rawValue: defaults.integer(forKey: Key.popToRootTimeout.rawValue))
            ?? .immediately
        escapeKeyBehavior =
            defaults.string(forKey: Key.escapeKeyBehavior.rawValue).flatMap(EscapeKeyBehavior.init)
            ?? .navigateBackOrClose
        appearance =
            defaults.string(forKey: Key.appearance.rawValue).flatMap(AppAppearance.init) ?? .system
        calcNumberStyle =
            defaults.string(forKey: Key.calcNumberStyle.rawValue).flatMap(CalcNumberStyle.init)
            ?? .system
        interfaceSize =
            defaults.string(forKey: Key.interfaceSize.rawValue).flatMap(InterfaceSize.init)
            ?? .standard
        compactMode =
            defaults.object(forKey: Key.compactMode.rawValue) == nil
            || defaults.bool(forKey: Key.compactMode.rawValue)
        compactBarCommands =
            defaults.stringArray(forKey: Key.compactBarCommands.rawValue)
            .flatMap(CommandID.compactBarCommands(from:)) ?? CommandID.defaultCompactBarCommands
        searchScopes =
            defaults.stringArray(forKey: Key.searchScopes.rawValue) ?? SearchScopes.defaults
        launcherShowsSuggestions =
            defaults.object(forKey: Key.launcherShowsSuggestions.rawValue) == nil
            || defaults.bool(forKey: Key.launcherShowsSuggestions.rawValue)
        rootSearchSensitivity =
            defaults.string(forKey: Key.rootSearchSensitivity.rawValue)
            .flatMap(SearchSensitivity.init) ?? .default
        openOnCursorScreen =
            defaults.object(forKey: Key.openOnCursorScreen.rawValue) == nil
            || defaults.bool(forKey: Key.openOnCursorScreen.rawValue)
        autoSwitchInputSourceID = defaults.string(forKey: Key.autoSwitchInputSource.rawValue)
        paletteDraggable = defaults.bool(forKey: Key.paletteDraggable.rawValue)
        animationsEnabled =
            defaults.object(forKey: Key.animationsEnabled.rawValue) == nil
            || defaults.bool(forKey: Key.animationsEnabled.rawValue)
        palettePositions =
            defaults.dictionary(forKey: Key.palettePosition.rawValue)
            as? [String: [Double]] ?? [:]
        paletteExpandedCenterDisplays =
            Set(defaults.stringArray(forKey: Key.paletteExpandedCenterDisplays.rawValue) ?? [])
        fileSearchEnabled = defaults.bool(forKey: Key.fileSearchEnabled.rawValue)
        // Unset seeds home; a stored empty array is a cleared list that searches nothing.
        fileSearchScopes =
            defaults.stringArray(forKey: Key.fileSearchScopes.rawValue)
            ?? FileSearchScope.defaultScopes
        fileSearchIgnorePatterns =
            defaults.stringArray(forKey: Key.fileSearchIgnorePatterns.rawValue) ?? []
        fileSearchRemovedDefaultPatterns =
            defaults.stringArray(forKey: Key.fileSearchRemovedDefaultPatterns.rawValue) ?? []
        fileSearchShowInLauncher = defaults.bool(forKey: Key.fileSearchShowInLauncher.rawValue)
        notesEnabled = defaults.bool(forKey: Key.notesEnabled.rawValue)
        dictationEnabled = defaults.bool(forKey: Key.dictationEnabled.rawValue)
        dictationMode =
            defaults.string(forKey: Key.dictationMode.rawValue)
            .flatMap(DictationMode.init) ?? .toggle
        dictationModel =
            defaults.string(forKey: Key.dictationModel.rawValue)
            .flatMap(DictationModel.init) ?? .redux
        dictationMicrophone = defaults.string(forKey: Key.dictationMicrophone.rawValue)
        dictationDestination =
            defaults.string(forKey: Key.dictationDestination.rawValue)
            .flatMap(DictationDestination.init) ?? .paste
        dictationAdaptsCapitalization =
            defaults.object(forKey: Key.dictationAdaptsCapitalization.rawValue) == nil
            || defaults.bool(forKey: Key.dictationAdaptsCapitalization.rawValue)
        dictationLiveInsertion = defaults.bool(forKey: Key.dictationLiveInsertion.rawValue)
        dictationPlaysSounds =
            defaults.object(forKey: Key.dictationPlaysSounds.rawValue) == nil
            || defaults.bool(forKey: Key.dictationPlaysSounds.rawValue)
        dictationIdleRelease =
            defaults.object(forKey: Key.dictationIdleRelease.rawValue)
            .flatMap { $0 as? Int }
            .flatMap(DictationIdleRelease.init(rawValue:)) ?? .oneMinute
        dictationLanguage =
            defaults.string(forKey: Key.dictationLanguage.rawValue)
            .flatMap(DictationLanguage.init(rawValue:))?.rawValue
        notesRendersMarkdown =
            defaults.object(forKey: Key.notesRendersMarkdown.rawValue) == nil
            || defaults.bool(forKey: Key.notesRendersMarkdown.rawValue)
        notesShowsFormattingBar =
            defaults.object(forKey: Key.notesShowsFormattingBar.rawValue) == nil
            || defaults.bool(forKey: Key.notesShowsFormattingBar.rawValue)
        notesShowsInMenuBar = defaults.bool(forKey: Key.notesShowsInMenuBar.rawValue)
        notesFolder = defaults.string(forKey: Key.notesFolder.rawValue)
        customCommandsEnabled = defaults.bool(forKey: Key.customCommandsEnabled.rawValue)
        customCommandsShowInLauncher =
            defaults.object(forKey: Key.customCommandsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.customCommandsShowInLauncher.rawValue)
        navigationEnabled = defaults.bool(forKey: Key.navigationEnabled.rawValue)
        menuSearchDisabledApps =
            defaults.stringArray(forKey: Key.menuSearchDisabledApps.rawValue) ?? []
        menuSearchShowsAppleMenu = defaults.bool(forKey: Key.menuSearchShowsAppleMenu.rawValue)
        windowManagementEnabled = defaults.bool(forKey: Key.windowManagementEnabled.rawValue)
        windowManagementShowInLauncher =
            defaults.object(forKey: Key.windowManagementShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.windowManagementShowInLauncher.rawValue)
        windowGap = defaults.integer(forKey: Key.windowGap.rawValue)
        windowCycle =
            defaults.string(forKey: Key.windowCycle.rawValue).flatMap(WindowCycle.init) ?? .off
        windowLayoutsShowInLauncher =
            defaults.object(forKey: Key.windowLayoutsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.windowLayoutsShowInLauncher.rawValue)
        windowRoomsShowInLauncher =
            defaults.object(forKey: Key.windowRoomsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.windowRoomsShowInLauncher.rawValue)
        settingsFileEnabled = defaults.bool(forKey: Key.settingsFileEnabled.rawValue)
    }
}
