import Foundation

enum CommandID: String, CaseIterable, Sendable {
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case pasteSequentially = "command:paste-sequentially"
    case searchEmoji = "command:search-emoji"
    case searchFiles = "command:search-files"
    case searchMenuItems = "command:search-menu-items"
    case openCamera = "command:open-camera"
    case captureScreenshot = "command:capture-screenshot"
    case openInBrowser = "command:open-in-browser"
    case createCustomCommand = "command:create-custom-command"
    case searchCustomCommands = "command:search-custom-commands"
    case define = "command:define"
    case showNotes = "command:show-notes"
    case createNote = "command:create-note"
    case searchNotes = "command:search-notes"
    case createWindowLayout = "command:create-window-layout"
    case captureWindowLayout = "command:capture-window-layout"
    case switchRoom = "command:switch-room"
    case createRoom = "command:create-room"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case importFromRaycast = "command:import-from-raycast"
    case checkForUpdates = "command:check-for-updates"
    case settings = "command:settings"
    case about = "command:about"
    case quit = "command:quit"

    static let defaultCompactBarCommands: [CommandID] = [
        .clipboardHistory, .searchEmoji, .searchFiles, .showNotes
    ]

    static let compactBarOptions: [CommandID] =
        defaultCompactBarCommands + [
            .searchNotes, .calculatorHistory, .searchCustomCommands, .searchMenuItems
        ]

    static let compactBarLimit = 4

    static func validCompactBarCommands(_ commands: [CommandID]) -> Bool {
        commands.count <= compactBarLimit && Set(commands).count == commands.count
            && commands.allSatisfy(compactBarOptions.contains)
    }

    static func compactBarCommands(from identifiers: [String]) -> [CommandID]? {
        let commands = identifiers.compactMap(CommandID.init(rawValue:))
        guard commands.count == identifiers.count, validCompactBarCommands(commands) else { return nil }
        return commands
    }

    var name: String {
        switch self {
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .pasteSequentially: return "Paste Sequentially"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .searchFiles: return "Search Files"
        case .searchMenuItems: return "Search Menu Bar Items"
        case .openCamera: return "Open Camera"
        case .captureScreenshot: return "Capture Screenshot"
        case .openInBrowser: return "Open in Browser"
        case .createCustomCommand: return "Create Custom Command"
        case .searchCustomCommands: return "Search Custom Commands"
        case .define: return "Define Word"
        case .showNotes: return "Show Notes"
        case .createNote: return "Create Note"
        case .searchNotes: return "Search Notes"
        case .createWindowLayout: return "Create Window Layout"
        case .captureWindowLayout: return "Create Layout from Current Windows"
        case .switchRoom: return "Switch Room"
        case .createRoom: return "Create Room"
        case .exportSettings: return "Export Backup"
        case .importSettings: return "Import Backup"
        case .importFromRaycast: return "Import from Raycast"
        case .checkForUpdates: return "Check for Updates"
        case .settings: return "Nanocast Settings"
        case .about: return "About Nanocast"
        case .quit: return "Quit Nanocast"
        }
    }

    var sfSymbol: String {
        switch self {
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "list.clipboard.fill"
        case .pasteSequentially: return "arrow.right.doc.on.clipboard"
        case .searchEmoji: return "face.smiling.inverse"
        case .searchFiles: return "doc.text.magnifyingglass"
        case .searchMenuItems: return "menubar.rectangle"
        case .openCamera: return "camera.fill"
        case .captureScreenshot: return "camera.viewfinder"
        case .openInBrowser: return "globe"
        case .createCustomCommand, .searchCustomCommands: return "terminal.fill"
        case .define: return "book.closed.fill"
        case .showNotes: return "text.page.fill"
        case .createNote: return "note.text.badge.plus"
        case .searchNotes: return "text.magnifyingglass"
        case .createWindowLayout: return "plus.rectangle.on.rectangle.fill"
        case .captureWindowLayout: return "macwindow.badge.plus"
        case .switchRoom: return "door.left.hand.open"
        case .createRoom: return "rectangle.stack.fill.badge.plus"
        case .exportSettings: return "square.and.arrow.up.fill"
        case .importSettings: return "square.and.arrow.down.fill"
        case .importFromRaycast: return "arrow.down.doc.fill"
        case .checkForUpdates: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        case .about: return "info.circle.fill"
        case .quit: return "power"
        }
    }

    var tint: IconTint {
        switch self {
        case .clipboardHistory, .pasteSequentially: return .indigo
        case .calculatorHistory, .checkForUpdates: return .green
        case .searchEmoji: return .orange
        case .searchFiles, .openInBrowser: return .blue
        case .searchMenuItems, .createCustomCommand, .searchCustomCommands: return .graphite
        case .openCamera, .settings, .about: return .gray
        case .define: return .brown
        case .captureScreenshot: return .purple
        case .quit: return .red
        case .showNotes, .createNote, .searchNotes: return .yellow
        case .createWindowLayout, .captureWindowLayout, .switchRoom, .createRoom: return .mint
        case .exportSettings, .importSettings, .importFromRaycast: return .cyan
        }
    }

    var suggestionPriority: Int? {
        switch self {
        case .clipboardHistory: 80
        case .searchFiles: 70
        case .searchEmoji: 50
        default: nil
        }
    }

    var isQueryDriven: Bool {
        self == .openInBrowser
    }

    var hotKeyAction: HotKeyAction? {
        isQueryDriven || self == .quit ? nil : .command(self)
    }
}
