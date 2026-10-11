import Foundation

enum HotKeyAction: Hashable, Sendable {
    case togglePalette
    case dictation
    case windowSwitcher
    case command(CommandID)
    case app(bundleID: String)
    case settingsPane(bundleID: String)
    case customCommand(id: UUID)
    case systemAction(id: SystemAction.ID)
    case windowCommand(id: WindowCommand.ID)
    case windowLayout(id: UUID)
    case windowRoom(id: UUID)
    case customWindowSize(id: UUID)

    var defaultsKey: String {
        switch self {
        case .togglePalette: "hotkey.togglePalette"
        case .dictation: "hotkey.dictation"
        case .windowSwitcher: "hotkey.windowSwitcher"
        case .command(let id): "hotkey." + id.rawValue
        case .app(let bundleID): "hotkey.app." + bundleID
        case .settingsPane(let bundleID): "hotkey.pane." + bundleID
        case .customCommand(let id): "hotkey.customCommand." + id.uuidString.lowercased()
        case .systemAction(let id): "hotkey.systemAction." + id.rawValue
        case .windowCommand(let id): "hotkey.windowCommand." + id.rawValue
        case .windowLayout(let id): "hotkey.windowLayout." + id.uuidString.lowercased()
        case .windowRoom(let id): "hotkey.windowRoom." + id.uuidString.lowercased()
        case .customWindowSize(let id):
            "hotkey.customWindowSize." + id.uuidString.lowercased()
        }
    }

    var acceptsModifierOnly: Bool { self != .windowSwitcher }

    static let builtInActions: [HotKeyAction] =
        [.togglePalette, .dictation, .windowSwitcher]
        + CommandID.allCases.compactMap(\.hotKeyAction)
}
