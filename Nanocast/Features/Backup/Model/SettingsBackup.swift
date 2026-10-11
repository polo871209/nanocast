import Foundation

struct SettingsBackup: Codable {

    var settings: SettingsData?
    var hotkeys: HotkeyBackup?
    var customCommands: [CustomCommand]?
    var windowLayouts: [WindowLayout]?
    var windowRooms: [Room]?
    var customWindowSizes: [CustomWindowSize]?
    var favoriteApps: [String]?
    var hiddenLauncherItems: [String]?
    var hiddenLauncherKinds: [String]?
    var launcherAliases: [String: String]?
    var pinnedEmoji: [String]?

    struct SettingsData: Codable {
        var clipboardEnabled: Bool?
        var clipboardRetentionDays: Int?
        var clipboardDefaultAction: String?
        var clipboardDisabledApps: [String]?
        var launchAtLogin: Bool?
        var hyperKey: String?
        var hyperKeyIncludesShift: Bool?
        var hyperKeyQuickPress: String?
        var hyperKeySecureInputCompatibility: Bool?
        var emojiSkinTone: String?
        var emojiGridColumns: Int?
        var showInMenuBar: Bool?
        var automaticallyCheckForUpdates: Bool?
        var popToRootSeconds: Int?
        var escapeKeyBehavior: String?
        var appearance: String?
        var calcNumberStyle: String?
        var interfaceSize: String?
        var compactMode: Bool?
        var compactBarCommands: [String]?
        var searchScopes: [String]?
        var launcherShowsSuggestions: Bool?
        var rootSearchSensitivity: String?
        var openOnCursorScreen: Bool?
        var paletteDraggable: Bool?
        var animationsEnabled: Bool?
        var fileSearchEnabled: Bool?
        var fileSearchScopes: [String]?
        var fileSearchIgnorePatterns: [String]?
        var fileSearchRemovedDefaultPatterns: [String]?
        var fileSearchShowInLauncher: Bool?
        var notesEnabled: Bool?
        var notesRendersMarkdown: Bool?
        var notesShowsFormattingBar: Bool?
        var customCommandsEnabled: Bool?
        var customCommandsShowInLauncher: Bool?
        var navigationEnabled: Bool?
        var menuSearchDisabledApps: [String]?
        var menuSearchShowsAppleMenu: Bool?
        var windowSwitcherExcludedApps: [String]?
        var windowManagementEnabled: Bool?
        var windowManagementShowInLauncher: Bool?
        var windowGap: Int?
        var windowCycle: String?
        var windowLayoutsShowInLauncher: Bool?
        var windowRoomsShowInLauncher: Bool?
    }

    struct HotkeyBackup: Codable {
        var togglePalette: HotKeyBinding?
        var commands: [String: HotKeyBinding]?
        var apps: [String: HotKeyBinding]?
        var panes: [String: HotKeyBinding]?
        var customCommands: [String: HotKeyBinding]?
        var systemActions: [String: HotKeyBinding]?
        var windowCommands: [String: HotKeyBinding]?
        var windowLayouts: [String: HotKeyBinding]?
        var windowRooms: [String: HotKeyBinding]?
        var customWindowSizes: [String: HotKeyBinding]?
    }

    struct ApplySummary {
        var settingsFields = 0
        var hotkeys = 0
        var favorites = 0
        var hiddenItems = 0
        var aliases = 0
        var pinnedEmoji = 0
        var customCommands = 0
        var windowLayouts = 0
        var windowRooms = 0
        var customWindowSizes = 0
    }
}

@MainActor
extension SettingsBackup {
    static func gather(from core: AppCore) -> SettingsBackup {
        let s = core.settings
        var backup = SettingsBackup()
        backup.settings = SettingsData(
            clipboardEnabled: s.clipboardEnabled,
            clipboardRetentionDays: s.clipboardRetention.rawValue,
            clipboardDefaultAction: s.clipboardDefaultAction.rawValue,
            clipboardDisabledApps: s.clipboardDisabledApps,
            launchAtLogin: s.launchAtLogin,
            hyperKey: s.hyperKey.rawValue,
            hyperKeyIncludesShift: s.hyperKeyIncludesShift,
            hyperKeyQuickPress: s.hyperKeyQuickPress.rawValue,
            hyperKeySecureInputCompatibility: s.hyperKeySecureInputCompatibility,
            emojiSkinTone: s.emojiSkinTone.rawValue,
            emojiGridColumns: s.emojiGridColumns.rawValue,
            showInMenuBar: s.showInMenuBar,
            automaticallyCheckForUpdates: s.automaticallyCheckForUpdates,
            popToRootSeconds: s.popToRootTimeout.rawValue,
            escapeKeyBehavior: s.escapeKeyBehavior.rawValue,
            appearance: s.appearance.rawValue,
            calcNumberStyle: s.calcNumberStyle.rawValue,
            interfaceSize: s.interfaceSize.rawValue,
            compactMode: s.compactMode,
            compactBarCommands: s.compactBarCommands.map(\.rawValue),
            searchScopes: s.searchScopes,
            launcherShowsSuggestions: s.launcherShowsSuggestions,
            rootSearchSensitivity: s.rootSearchSensitivity.rawValue,
            openOnCursorScreen: s.openOnCursorScreen,
            paletteDraggable: s.paletteDraggable,
            animationsEnabled: s.animationsEnabled,
            fileSearchEnabled: s.fileSearchEnabled,
            fileSearchScopes: s.fileSearchScopes,
            fileSearchIgnorePatterns: s.fileSearchIgnorePatterns,
            fileSearchRemovedDefaultPatterns: s.fileSearchRemovedDefaultPatterns,
            fileSearchShowInLauncher: s.fileSearchShowInLauncher,
            notesEnabled: s.notesEnabled,
            notesRendersMarkdown: s.notesRendersMarkdown,
            notesShowsFormattingBar: s.notesShowsFormattingBar,
            customCommandsEnabled: s.customCommandsEnabled,
            customCommandsShowInLauncher: s.customCommandsShowInLauncher,
            navigationEnabled: s.navigationEnabled,
            menuSearchDisabledApps: s.menuSearchDisabledApps,
            menuSearchShowsAppleMenu: s.menuSearchShowsAppleMenu,
            windowSwitcherExcludedApps: s.windowSwitcherExcludedApps,
            windowManagementEnabled: s.windowManagementEnabled,
            windowManagementShowInLauncher: s.windowManagementShowInLauncher,
            windowGap: s.windowGap,
            windowCycle: s.windowCycle.rawValue,
            windowLayoutsShowInLauncher: s.windowLayoutsShowInLauncher,
            windowRoomsShowInLauncher: s.windowRoomsShowInLauncher)

        let hk = core.hotKeys
        var hotkeys = HotkeyBackup()
        hotkeys.togglePalette = hk.binding(for: .togglePalette)
        hotkeys.commands = Dictionary(
            uniqueKeysWithValues: CommandID.allCases.compactMap { id in
                id.hotKeyAction.flatMap(hk.binding(for:)).map { (id.rawValue, $0) }
            })
        hotkeys.apps = Dictionary(
            uniqueKeysWithValues: hk.boundBundleIDs.compactMap { id in
                hk.binding(for: .app(bundleID: id)).map { (id, $0) }
            })
        hotkeys.panes = Dictionary(
            uniqueKeysWithValues: hk.boundPaneBundleIDs.compactMap { id in
                hk.binding(for: .settingsPane(bundleID: id)).map { (id, $0) }
            })
        hotkeys.customCommands = Dictionary(
            uniqueKeysWithValues: hk.boundCustomCommandIDs.compactMap { id in
                hk.binding(for: .customCommand(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.systemActions = Dictionary(
            uniqueKeysWithValues: SystemAction.ID.allCases.compactMap { id in
                hk.binding(for: .systemAction(id: id)).map { (id.rawValue, $0) }
            })
        hotkeys.windowCommands = Dictionary(
            uniqueKeysWithValues: WindowCommand.ID.allCases.compactMap { id in
                hk.binding(for: .windowCommand(id: id)).map { (id.rawValue, $0) }
            })
        hotkeys.windowLayouts = Dictionary(
            uniqueKeysWithValues: hk.boundWindowLayoutIDs.compactMap { id in
                hk.binding(for: .windowLayout(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.windowRooms = Dictionary(
            uniqueKeysWithValues: hk.boundWindowRoomIDs.compactMap { id in
                hk.binding(for: .windowRoom(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.customWindowSizes = Dictionary(
            uniqueKeysWithValues: hk.boundCustomWindowSizeIDs.compactMap { id in
                hk.binding(for: .customWindowSize(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        backup.hotkeys = hotkeys

        backup.customCommands = core.customCommands.commands
        backup.windowLayouts = core.windowLayouts.layouts
        backup.windowRooms = core.rooms.rooms
        backup.customWindowSizes = core.customWindowSizes.sizes
        backup.favoriteApps = core.favorites.keys
        backup.hiddenLauncherItems = Array(core.visibility.hiddenItemKeys)
        backup.hiddenLauncherKinds = Array(core.visibility.disabledKinds)
        backup.launcherAliases = core.aliases.aliases
        backup.pinnedEmoji = core.pinnedEmoji.glyphs
        return backup
    }

    @discardableResult
    func apply(to core: AppCore) -> ApplySummary {
        var summary = ApplySummary()
        if let s = settings { summary.settingsFields = applySettings(s, to: core) }
        if let customCommands {
            summary.customCommands = core.customCommandCoordinator.replaceCustomCommands(customCommands)
        }
        if let windowLayouts {
            summary.windowLayouts =
                core.windowLayoutCoordinator.replaceWindowLayouts(windowLayouts)
        }
        if let windowRooms {
            summary.windowRooms = core.roomCoordinator.replaceRooms(windowRooms)
        }
        if let customWindowSizes {
            summary.customWindowSizes =
                core.customWindowSizeCoordinator.replaceCustomWindowSizes(customWindowSizes)
        }
        if let hotkeys { summary.hotkeys = applyHotkeys(hotkeys, to: core) }
        if let favoriteApps {
            core.favorites.replace(keys: favoriteApps)
            summary.favorites = favoriteApps.count
        }
        if hiddenLauncherItems != nil || hiddenLauncherKinds != nil {
            let items = hiddenLauncherItems ?? Array(core.visibility.hiddenItemKeys)
            let kinds = hiddenLauncherKinds ?? Array(core.visibility.disabledKinds)
            core.visibility.replace(hiddenItems: items, disabledKinds: kinds)
            summary.hiddenItems = items.count
        }
        if let launcherAliases {
            core.aliases.replace(launcherAliases)
            summary.aliases = core.aliases.aliases.count
        }
        if let pinnedEmoji {
            core.pinnedEmoji.replace(pinnedEmoji)
            summary.pinnedEmoji = core.pinnedEmoji.glyphs.count
        }
        return summary
    }

    private func applySettings(_ s: SettingsData, to core: AppCore) -> Int {
        let settings = core.settings
        var count = 0
        if let flag = s.clipboardEnabled {
            settings.clipboardEnabled = flag
            count += 1
        }
        if let days = s.clipboardRetentionDays, let retention = ClipboardRetention(rawValue: days) {
            settings.clipboardRetention = retention
            count += 1
        }
        if let apps = s.clipboardDisabledApps {
            settings.clipboardDisabledApps = apps
            count += 1
        }
        if let raw = s.clipboardDefaultAction, let action = ClipboardDefaultAction(rawValue: raw) {
            settings.clipboardDefaultAction = action
            count += 1
        }
        if let launch = s.launchAtLogin {
            settings.launchAtLogin = launch
            count += 1
        }
        if let raw = s.hyperKey, let key = HyperKeyPhysicalKey(rawValue: raw) {
            settings.hyperKey = key
            count += 1
        }
        if let flag = s.hyperKeyIncludesShift {
            settings.hyperKeyIncludesShift = flag
            count += 1
        }
        if let raw = s.hyperKeyQuickPress, let quick = HyperKeyQuickPress(rawValue: raw) {
            settings.hyperKeyQuickPress = quick
            count += 1
        }
        if let flag = s.hyperKeySecureInputCompatibility {
            settings.hyperKeySecureInputCompatibility = flag
            count += 1
        }
        if let raw = s.emojiSkinTone, let tone = EmojiSkinTone(rawValue: raw) {
            settings.emojiSkinTone = tone
            count += 1
        }
        if let raw = s.emojiGridColumns, let columns = EmojiGridColumns(rawValue: raw) {
            settings.emojiGridColumns = columns
            count += 1
        }
        if let show = s.showInMenuBar {
            settings.showInMenuBar = show
            count += 1
        }
        if let automaticallyCheck = s.automaticallyCheckForUpdates {
            settings.automaticallyCheckForUpdates = automaticallyCheck
            count += 1
        }
        if let secs = s.popToRootSeconds, let timeout = PopToRootTimeout(rawValue: secs) {
            settings.popToRootTimeout = timeout
            count += 1
        }
        if let raw = s.escapeKeyBehavior, let behavior = EscapeKeyBehavior(rawValue: raw) {
            settings.escapeKeyBehavior = behavior
            count += 1
        }
        if let raw = s.interfaceSize, let size = InterfaceSize(rawValue: raw) {
            settings.interfaceSize = size
            count += 1
        }
        if let raw = s.appearance, let appearance = AppAppearance(rawValue: raw) {
            settings.appearance = appearance
            count += 1
        }
        if let raw = s.calcNumberStyle, let style = CalcNumberStyle(rawValue: raw) {
            settings.calcNumberStyle = style
            count += 1
        }
        if let flag = s.compactMode {
            settings.compactMode = flag
            count += 1
        }
        if let identifiers = s.compactBarCommands,
            let commands = CommandID.compactBarCommands(from: identifiers)
        {
            settings.compactBarCommands = commands
            count += 1
        }
        if let scopes = s.searchScopes {
            settings.searchScopes = SearchScopes.normalize(scopes)
            count += 1
        }
        if let flag = s.launcherShowsSuggestions {
            settings.launcherShowsSuggestions = flag
            count += 1
        }
        if let raw = s.rootSearchSensitivity, let sensitivity = SearchSensitivity(rawValue: raw) {
            settings.rootSearchSensitivity = sensitivity
            count += 1
        }
        if let flag = s.openOnCursorScreen {
            settings.openOnCursorScreen = flag
            count += 1
        }
        if let flag = s.paletteDraggable {
            settings.paletteDraggable = flag
            count += 1
        }
        if let flag = s.animationsEnabled {
            settings.animationsEnabled = flag
            count += 1
        }
        if let flag = s.fileSearchEnabled {
            settings.fileSearchEnabled = flag
            count += 1
        }
        if let scopes = s.fileSearchScopes {
            settings.fileSearchScopes = scopes
            count += 1
        }
        if let patterns = s.fileSearchIgnorePatterns {
            settings.fileSearchIgnorePatterns = patterns
            count += 1
        }
        if let patterns = s.fileSearchRemovedDefaultPatterns {
            settings.fileSearchRemovedDefaultPatterns = patterns
            count += 1
        }
        if let flag = s.fileSearchShowInLauncher {
            settings.fileSearchShowInLauncher = flag
            count += 1
        }
        if let flag = s.notesEnabled {
            settings.notesEnabled = flag
            count += 1
        }
        if let flag = s.notesRendersMarkdown {
            settings.notesRendersMarkdown = flag
            count += 1
        }
        if let flag = s.notesShowsFormattingBar {
            settings.notesShowsFormattingBar = flag
            count += 1
        }
        if let flag = s.customCommandsEnabled {
            settings.customCommandsEnabled = flag
            count += 1
        }
        if let flag = s.customCommandsShowInLauncher {
            settings.customCommandsShowInLauncher = flag
            count += 1
        }
        if let flag = s.navigationEnabled {
            settings.navigationEnabled = flag
            count += 1
        }
        if let apps = s.menuSearchDisabledApps {
            settings.menuSearchDisabledApps = apps
            count += 1
        }
        if let flag = s.menuSearchShowsAppleMenu {
            settings.menuSearchShowsAppleMenu = flag
            count += 1
        }
        if let apps = s.windowSwitcherExcludedApps {
            settings.windowSwitcherExcludedApps = apps
            count += 1
        }
        if let flag = s.windowManagementEnabled {
            settings.windowManagementEnabled = flag
            count += 1
        }
        if let flag = s.windowManagementShowInLauncher {
            settings.windowManagementShowInLauncher = flag
            count += 1
        }
        if let gap = s.windowGap {
            settings.windowGap = gap
            count += 1
        }
        if let raw = s.windowCycle, let cycle = WindowCycle(rawValue: raw) {
            settings.windowCycle = cycle
            count += 1
        }
        if let flag = s.windowLayoutsShowInLauncher {
            settings.windowLayoutsShowInLauncher = flag
            count += 1
        }
        if let flag = s.windowRoomsShowInLauncher {
            settings.windowRoomsShowInLauncher = flag
            count += 1
        }
        return count
    }

    private func applyHotkeys(_ hotkeys: HotkeyBackup, to core: AppCore) -> Int {
        let hk = core.hotKeys
        var count = 0
        func apply(_ binding: HotKeyBinding, _ action: HotKeyAction) {
            guard hk.conflictOwner(of: binding, excluding: action) == nil else { return }
            hk.setBinding(binding, for: action)
            count += 1
        }
        if let b = hotkeys.togglePalette { apply(b, .togglePalette) }
        for (rawID, b) in hotkeys.commands ?? [:] {
            guard let action = CommandID(rawValue: rawID)?.hotKeyAction else { continue }
            apply(b, action)
        }
        for (id, b) in hotkeys.apps ?? [:] { apply(b, .app(bundleID: id)) }
        for (id, b) in hotkeys.panes ?? [:] { apply(b, .settingsPane(bundleID: id)) }
        for (rawID, b) in hotkeys.customCommands ?? [:] {
            guard let id = UUID(uuidString: rawID), core.customCommands.command(id: id) != nil else {
                continue
            }
            apply(b, .customCommand(id: id))
        }
        for (rawID, b) in hotkeys.systemActions ?? [:] {
            guard let id = SystemAction.ID(rawValue: rawID) else { continue }
            apply(b, .systemAction(id: id))
        }
        for (rawID, b) in hotkeys.windowCommands ?? [:] {
            guard let id = WindowCommand.ID(rawValue: rawID) else { continue }
            apply(b, .windowCommand(id: id))
        }
        for (rawID, b) in hotkeys.windowLayouts ?? [:] {
            guard let id = UUID(uuidString: rawID), core.windowLayouts.layout(id: id) != nil
            else { continue }
            apply(b, .windowLayout(id: id))
        }
        for (rawID, b) in hotkeys.windowRooms ?? [:] {
            guard let id = UUID(uuidString: rawID), core.rooms.room(id: id) != nil else { continue }
            apply(b, .windowRoom(id: id))
        }
        for (rawID, b) in hotkeys.customWindowSizes ?? [:] {
            guard let id = UUID(uuidString: rawID), core.customWindowSizes.size(id: id) != nil
            else { continue }
            apply(b, .customWindowSize(id: id))
        }
        return count
    }
}

extension SettingsBackup {
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    init(json: Data) throws {
        self = try JSONDecoder().decode(SettingsBackup.self, from: json)
    }
}
