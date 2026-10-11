import Foundation

enum SettingsTab: CaseIterable, Identifiable {
    case general, applications, systemSettings, systemActions, commands, clipboard, fileSearch,
        windowManagement, navigation, notes, emoji, dictation, permissions, backup, about
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .applications: return String(localized: "Applications")
        case .systemSettings: return String(localized: "System Settings")
        case .systemActions: return String(localized: "System Actions")
        case .commands: return String(localized: "Commands")
        case .dictation: return String(localized: "Dictation")
        case .fileSearch: return String(localized: "File Search")
        case .notes: return String(localized: "Notes")
        case .navigation: return String(localized: "Navigation")
        case .windowManagement: return String(localized: "Window Management")
        case .clipboard: return String(localized: "Clipboard")
        case .emoji: return String(localized: "Emoji & Symbols")
        case .permissions: return String(localized: "Permissions")
        case .backup: return String(localized: "Backup")
        case .about: return String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .applications: return "square.grid.2x2"
        case .systemSettings: return "gearshape"
        case .systemActions: return "bolt"
        case .commands: return "terminal"
        case .dictation: return "waveform"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .notes: return "text.page"
        case .navigation: return "arrow.left.arrow.right"
        case .windowManagement: return "macwindow"
        case .clipboard: return "doc.on.clipboard"
        case .emoji: return "face.smiling"
        case .permissions: return "lock.shield"
        case .backup: return "arrow.up.arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

enum SettingsSection: CaseIterable, Identifiable {
    case general, launcher, features, advanced
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .launcher: return String(localized: "Launcher")
        case .features: return String(localized: "Features")
        case .advanced: return String(localized: "Advanced")
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .general: return [.general, .permissions]
        case .launcher:
            return [.applications, .systemSettings, .systemActions, .commands]
        case .features:
            return [
                .clipboard, .fileSearch, .windowManagement, .navigation, .notes, .emoji, .dictation
            ]
        case .advanced: return [.backup, .about]
        }
    }
}
