import AppKit

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case calculatorHistory
    case emoji
    case fileSearch
    case menuSearch
    case switchWindows
    case rooms
    case roomWindows
    case customCommandEditor
    case customCommands
    case uninstall
    case dictionary

    var id: String { rawValue }

    var isNativeEditor: Bool {
        self == .customCommandEditor
    }

    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .menuSearch: return "menubar.rectangle"
        case .switchWindows: return "macwindow.on.rectangle"
        case .rooms: return "door.left.hand.open"
        case .roomWindows: return "macwindow.badge.plus"
        case .customCommandEditor, .customCommands: return CustomCommand.sfSymbol
        case .uninstall: return "trash"
        case .dictionary: return "book.closed"
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return String(localized: "Search for apps and commands…")
        case .clipboard: return String(localized: "Type to filter entries…")
        case .calculatorHistory:
            return String(localized: "Do math, convert units, or search your past calculations…")
        case .emoji: return String(localized: "Search emoji and symbols…")
        case .fileSearch: return String(localized: "Search files and folders…")
        case .menuSearch: return String(localized: "Search menu bar items…")
        case .switchWindows: return String(localized: "Search open windows…")
        case .rooms: return String(localized: "Search rooms, or name a new one…")
        case .roomWindows: return String(localized: "Search windows, or type an app to add…")
        case .customCommandEditor: return String(localized: "Command editor")
        case .customCommands: return String(localized: "Search custom commands…")
        case .uninstall: return String(localized: "Filter files and folders by name…")
        case .dictionary: return String(localized: "Look up a word…")
        }
    }
}

struct PasteTarget: Equatable {
    let name: String
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { String(localized: "Paste to \(name)") }
}
