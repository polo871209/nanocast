import Foundation

enum SettingsTab: CaseIterable, Identifiable {
    case general, applications, systemSettings, systemActions, commands, clipboard, fileSearch,
        screen, windowManagement, navigation, notes, emoji, permissions, backup, about
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .applications: return "Applications"
        case .systemSettings: return "System Settings"
        case .systemActions: return "System Actions"
        case .commands: return "Commands"
        case .fileSearch: return "File Search"
        case .notes: return "Notes"
        case .navigation: return "Navigation"
        case .windowManagement: return "Window Management"
        case .clipboard: return "Clipboard"
        case .screen: return "Screen"
        case .emoji: return "Emoji & Symbols"
        case .permissions: return "Permissions"
        case .backup: return "Backup"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .applications: return "square.grid.2x2.fill"
        case .systemSettings: return "gearshape.fill"
        case .systemActions: return "bolt.fill"
        case .commands: return "terminal.fill"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .notes: return "text.page.fill"
        case .navigation: return "arrow.left.arrow.right"
        case .windowManagement: return "macwindow"
        case .clipboard: return "list.clipboard.fill"
        case .screen: return "display"
        case .emoji: return "face.smiling.inverse"
        case .permissions: return "lock.shield.fill"
        case .backup: return "arrow.up.arrow.down.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: IconTint {
        switch self {
        case .general, .systemSettings, .about: return .gray
        case .commands, .navigation: return .graphite
        case .permissions, .fileSearch: return .blue
        case .applications, .backup: return .cyan
        case .windowManagement: return .mint
        case .notes: return .yellow
        case .systemActions, .emoji: return .orange
        case .clipboard: return .indigo
        case .screen: return .purple
        }
    }
}

enum SettingsSection: CaseIterable, Identifiable {
    case general, launcher, features, advanced
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .launcher: return "Launcher"
        case .features: return "Features"
        case .advanced: return "Advanced"
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .general: return [.general, .permissions]
        case .launcher:
            return [.applications, .systemSettings, .systemActions, .commands]
        case .features:
            return [
                .clipboard, .fileSearch, .screen, .windowManagement, .navigation, .notes,
                .emoji
            ]
        case .advanced: return [.backup, .about]
        }
    }
}
