import Foundation

enum CommandCatalog {
    nonisolated static let all: [AppEntry] =
        CommandID.allCases
        .filter { !$0.isQueryDriven }
        .map { makeEntry($0) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    nonisolated static func entries(ownedBy owner: SettingsTab) -> [AppEntry] {
        owner.ownedCommands.map { makeEntry($0) }
    }

    static func command(for entry: AppEntry) -> CommandID? {
        CommandID(rawValue: entry.id)
    }

    static func entry(for command: CommandID) -> AppEntry? {
        all.first { $0.id == command.rawValue }
    }

    static func isQueryDriven(_ entry: AppEntry) -> Bool {
        command(for: entry)?.isQueryDriven ?? false
    }

    static func openInBrowser(for query: String) -> AppEntry? {
        guard case .web(let url)? = LinkDestination.detect(query) else { return nil }
        return makeEntry(.openInBrowser, url: url, subtitle: String(localized: "URL"))
    }

    nonisolated static func makeEntry(
        _ id: CommandID, url: URL? = nil, subtitle: String? = nil
    ) -> AppEntry {
        AppEntry(
            id: id.rawValue, name: id.name, url: url ?? placeholderURL(id), bundleID: nil,
            kind: .command, settingsOwner: id.owner, subtitle: subtitle,
            alternateTitles: [id.englishName])
    }

    nonisolated private static func placeholderURL(_ id: CommandID) -> URL {
        URL(string: "nanocast://" + id.rawValue.replacingOccurrences(of: ":", with: "/"))!
    }
}

extension SettingsTab {
    var ownedCommands: [CommandID] {
        switch self {
        case .commands: [.createCustomCommand, .searchCustomCommands]
        case .fileSearch: [.searchFiles]
        case .notes: [.showNotes, .createNote, .searchNotes]
        case .navigation: [.searchMenuItems]
        case .windowManagement:
            [.createWindowLayout, .captureWindowLayout, .switchRoom, .createRoom]
        case .clipboard: [.clipboardHistory, .pasteSequentially]
        case .emoji: [.searchEmoji]
        default: []
        }
    }
}

extension CommandID {
    var owner: SettingsTab? { Self.owners[self] }

    nonisolated private static let owners: [CommandID: SettingsTab] =
        SettingsTab.allCases.reduce(into: [:]) { table, tab in
            for command in tab.ownedCommands { table[command] = tab }
        }
}
