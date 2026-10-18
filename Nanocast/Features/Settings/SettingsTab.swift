import Foundation

enum SettingsTab: CaseIterable, Identifiable {
    case general, applications, systemSettings, systemActions, commands, clipboard, fileSearch,
        fileTools, screenshot, windowManagement, navigation, notes, emoji, dictation, permissions, backup, about
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .applications: return "Applications"
        case .systemSettings: return "System Settings"
        case .systemActions: return "System Actions"
        case .commands: return "Commands"
        case .dictation: return "Dictation"
        case .fileSearch: return "File Search"
        case .fileTools: return "File Tools"
        case .notes: return "Notes"
        case .navigation: return "Navigation"
        case .windowManagement: return "Window Management"
        case .clipboard: return "Clipboard"
        case .screenshot: return "Screenshot"
        case .emoji: return "Emoji & Symbols"
        case .permissions: return "Permissions"
        case .backup: return "Backup"
        case .about: return "About"
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
        case .fileTools: return "wand.and.sparkles"
        case .notes: return "text.page"
        case .navigation: return "arrow.left.arrow.right"
        case .windowManagement: return "macwindow"
        case .clipboard: return "doc.on.clipboard"
        case .screenshot: return "camera.viewfinder"
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
                .clipboard, .fileSearch, .fileTools, .screenshot, .windowManagement, .navigation, .notes,
                .emoji, .dictation
            ]
        case .advanced: return [.backup, .about]
        }
    }
}
