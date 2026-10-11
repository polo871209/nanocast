import Foundation

struct SettingsAnchor: Hashable, Sendable {
    let tab: SettingsTab
    let title: String

    init(tab: SettingsTab, title: LocalizedStringResource) {
        self.tab = tab
        self.title = String(localized: title)
    }
}

extension SettingsAnchor {
    static let generalGlobalShortcuts = Self(tab: .general, title: "Global Shortcuts")
    static let generalSearch = Self(tab: .general, title: "Search")
    static let generalHyperKey = Self(tab: .general, title: "Hyper Key")
    static let generalAppearance = Self(tab: .general, title: "Appearance")
    static let generalCalculator = Self(tab: .general, title: "Calculator")
    static let generalGeneral = Self(tab: .general, title: "General")

    static let applicationsSearchScopes = Self(tab: .applications, title: "Search Scopes")
    static let applicationsApplications = Self(tab: .applications, title: "Applications")

    static let systemSettingsSystemSettings = Self(tab: .systemSettings, title: "System Settings")

    static let systemActionsSystemActions = Self(tab: .systemActions, title: "System Actions")

    static let commandsCommands = Self(tab: .commands, title: "Commands")
    static let commandsCustomCommands = Self(tab: .commands, title: "Custom Commands")

    static let dictationDictation = Self(tab: .dictation, title: "Dictation")
    static let dictationCommands = Self(tab: .dictation, title: "Commands")
    static let dictationModel = Self(tab: .dictation, title: "Model")
    static let dictationMemory = Self(tab: .dictation, title: "Memory")
    static let dictationOutput = Self(tab: .dictation, title: "Output")

    static let fileSearchFileSearch = Self(tab: .fileSearch, title: "File Search")
    static let fileSearchFullDiskAccess = Self(tab: .fileSearch, title: "Full Disk Access")
    static let fileSearchIndex = Self(tab: .fileSearch, title: "Index")
    static let fileSearchCommands = Self(tab: .fileSearch, title: "Commands")
    static let fileSearchSearchScopes = Self(tab: .fileSearch, title: "Search Scopes")
    static let fileSearchIgnorePatterns = Self(tab: .fileSearch, title: "Ignore Patterns")

    static let notesNotes = Self(tab: .notes, title: "Notes")
    static let notesOptions = Self(tab: .notes, title: "Options")
    static let notesCommands = Self(tab: .notes, title: "Commands")

    static let navigationNavigation = Self(tab: .navigation, title: "Navigation")
    static let navigationCommands = Self(tab: .navigation, title: "Commands")
    static let navigationMenuSearch = Self(tab: .navigation, title: "Search Menu Bar Items")

    static let windowManagementWindowManagement = Self(
        tab: .windowManagement, title: "Window Management")
    static let windowManagementLayouts = Self(tab: .windowManagement, title: "Window Layouts")
    static let windowManagementRooms = Self(tab: .windowManagement, title: "Rooms")
    static let windowManagementLayoutCommands = Self(
        tab: .windowManagement, title: "Layout and Room Commands")
    static let windowManagementOptions = Self(tab: .windowManagement, title: "Options")
    static let windowManagementCustomSizes = Self(tab: .windowManagement, title: "Custom Sizes")

    static let clipboardClipboard = Self(tab: .clipboard, title: "Clipboard")
    static let clipboardCommands = Self(tab: .clipboard, title: "Commands")
    static let clipboardHistory = Self(tab: .clipboard, title: "History")
    static let clipboardDisabledApplications = Self(
        tab: .clipboard, title: "Excluded Applications")

    static let emojiCommands = Self(tab: .emoji, title: "Commands")
    static let emojiAppearance = Self(tab: .emoji, title: "Appearance")

    static let permissionsAccessibility = Self(tab: .permissions, title: "Accessibility")
    static let permissionsFullDiskAccess = Self(tab: .permissions, title: "Full Disk Access")
    static let permissionsMicrophone = Self(tab: .permissions, title: "Microphone")

    static let backupExport = Self(tab: .backup, title: "Export")
    static let backupImport = Self(tab: .backup, title: "Import")
    static let backupImportFromRaycast = Self(tab: .backup, title: "Import from Raycast")
    static let backupSettingsFile = Self(tab: .backup, title: "Settings File")

    static let aboutAbout = Self(tab: .about, title: "About")
    static let aboutLinks = Self(tab: .about, title: "Links")
}

enum SettingsTarget: Hashable, Sendable {
    case section(SettingsAnchor)
    case row(SettingsAnchor, String)

    var anchor: SettingsAnchor {
        switch self {
        case .section(let anchor), .row(let anchor, _): return anchor
        }
    }

    var tab: SettingsTab { anchor.tab }
}

struct SettingsScrollRequest: Equatable, Sendable {
    let target: SettingsTarget
    let token: Int
}
