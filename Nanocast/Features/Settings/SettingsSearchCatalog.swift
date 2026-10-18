import Foundation

struct SettingsSearchEntry: Identifiable, Hashable, Sendable {
    let tab: SettingsTab
    let target: SettingsTarget?
    let title: String
    let keywords: [String]

    private init(_ target: SettingsTarget, _ title: String, _ keywords: [String]) {
        self.tab = target.tab
        self.target = target
        self.title = title
        self.keywords = keywords
    }

    init(_ anchor: SettingsAnchor, _ title: String, keywords: [String] = []) {
        self.init(.row(anchor, title), title, keywords)
    }

    init(group anchor: SettingsAnchor, _ title: String, keywords: [String] = []) {
        self.init(.section(anchor), title, keywords)
    }

    init(pane: SettingsTab, keywords: [String] = []) {
        self.tab = pane
        self.target = nil
        self.title = pane.title
        self.keywords = keywords
    }

    var anchor: SettingsAnchor? { target?.anchor }

    var id: String { "\(tab.title)/\(anchor?.title ?? "")/\(title)" }

    var breadcrumb: String {
        guard let anchor, anchor.title != tab.title else { return tab.title }
        return "\(tab.title) › \(anchor.title)"
    }
}

enum SettingsSearchCatalog {
    struct Query: Sendable {
        let terms: [FuzzyMatch.Query]

        init(_ raw: String) {
            terms = raw.split(whereSeparator: \Character.isWhitespace).map {
                FuzzyMatch.Query(String($0))
            }
        }

        var isEmpty: Bool { terms.isEmpty }
    }

    static func results(for raw: String, limit: Int = 50) -> [SettingsSearchEntry] {
        let query = Query(raw)
        guard !query.isEmpty else { return [] }
        return
            entries
            .enumerated()
            .compactMap { item -> (entry: SettingsSearchEntry, score: Int, rank: Int)? in
                guard let score = score(query, item.element) else { return nil }
                return (item.element, score, item.offset)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.rank < $1.rank }
            .prefix(limit)
            .map(\.entry)
    }

    private static func score(_ query: Query, _ entry: SettingsSearchEntry) -> Int? {
        var titleScore = 0
        var titleMatches = 0
        for term in query.terms {
            if let match = FuzzyMatch.match(term, candidate: entry.title) {
                titleMatches += 1
                titleScore += match.score
                continue
            }
            guard
                entry.keywords.contains(where: { FuzzyMatch.match(term, candidate: $0) != nil })
                    || FuzzyMatch.match(term, candidate: entry.breadcrumb) != nil
            else { return nil }
        }

        let band: Int
        if titleMatches == query.terms.count {
            band = 2_000_000
        } else if titleMatches > 0 {
            band = 1_000_000
        } else {
            band = 0
        }
        return band + titleScore + (entry.anchor == nil ? 500_000 : 0)
    }

    static let entries: [SettingsSearchEntry] =
        general + applications + systemSettings + systemActions + commands + clipboard
        + fileSearch + fileTools + screenshot + windowManagement + navigation + notes + emoji + dictation
        + permissions + backup + about

    private static let general: [SettingsSearchEntry] = [
        .init(pane: .general, keywords: ["preferences", "settings"]),
        .init(
            .generalGlobalShortcuts, "Show Launcher",
            keywords: ["hotkey", "shortcut", "summon", "palette"]),
        .init(
            .generalGeneral, "Launch at login",
            keywords: ["startup", "login item", "start", "boot"]),
        .init(
            .generalGeneral, "Show in menu bar",
            keywords: ["menubar", "status item", "icon", "hide"]),
        .init(
            .generalGeneral, "Automatically check for updates",
            keywords: ["software", "update", "automatic", "disable", "popup"]),
        .init(
            .generalGeneral, "Pop to Root Search",
            keywords: ["reset", "timeout", "back"]),
        .init(
            .generalGeneral, "Escape Key Behavior",
            keywords: ["escape", "esc", "back", "close", "navigate"]),
        .init(
            .generalGeneral, "Auto-switch input source",
            keywords: ["keyboard", "layout", "language", "abc"]),
        .init(
            .generalAppearance, "Appearance",
            keywords: ["dark", "light", "mode", "theme"]),
        .init(
            .generalAppearance, "Show animations",
            keywords: ["motion", "transitions", "reduce motion", "effects", "instant"]),
        .init(
            .generalAppearance, "Interface size",
            keywords: ["text size", "font size", "scale", "zoom", "bigger", "larger", "legible"]),
        .init(
            .generalAppearance, "Window mode",
            keywords: ["compact", "expanded", "slim", "search bar", "small"]),
        .init(
            group: .generalCompactShortcuts, "Compact Shortcuts",
            keywords: ["slots", "buttons", "reorder", "clipboard", "files", "emoji", "notes"]),
        .init(
            .generalAppearance, "Follow the cursor across displays",
            keywords: ["monitor", "screen", "pointer", "multi display"]),
        .init(
            .generalAppearance, "Drag to move the launcher",
            keywords: ["move", "position", "window"]),
        .init(
            .generalHyperKey, "Hyper Key",
            keywords: ["modifier", "remap", "caps lock", "capslock"]),
        .init(
            .generalHyperKey, "Quick Press",
            keywords: ["tap", "escape", "single press"]),
        .init(
            .generalHyperKey, "Include Shift (⇧)",
            keywords: ["modifier", "chord"]),
        .init(
            .generalHyperKey, "Secure Input Compatibility",
            keywords: ["password", "secure input", "right control"]),
        .init(
            .generalCalculator, "Number format",
            keywords: ["decimal", "comma", "separator", "locale", "region", "thousands"]),
        .init(
            .generalSearch, "Show suggestions",
            keywords: ["frequent", "recent", "recommended", "empty", "root search"]),
        .init(
            .generalSearch, "Search sensitivity",
            keywords: ["fuzzy", "strict", "loose", "matching", "typo", "root search"]),
        .init(
            .generalSearch, "Learned ranking",
            keywords: ["reset", "history", "order", "privacy"])
    ]

    private static let applications: [SettingsSearchEntry] = [
        .init(pane: .applications, keywords: ["apps", "index", "launcher"]),
        .init(
            .applicationsApplications, "Enable Applications",
            keywords: ["hide apps", "visibility"]),
        .init(
            group: .applicationsSearchScopes, "Search Scopes",
            keywords: ["folders", "indexed", "locations", "add folder"]),
        .init(
            group: .applicationsApplications, "Aliases and shortcuts",
            keywords: ["alias", "hotkey", "per app", "hide"])
    ]

    private static let systemSettings: [SettingsSearchEntry] = [
        .init(
            pane: .systemSettings,
            keywords: ["panes", "preferences", "macos"]),
        .init(
            .systemSettingsSystemSettings, "Enable System Settings",
            keywords: ["hide panes", "visibility"])
    ]

    private static let systemActions: [SettingsSearchEntry] = [
        .init(
            pane: .systemActions,
            keywords: ["sleep", "lock", "restart", "shut down", "empty trash"]),
        .init(
            .systemActionsSystemActions, "Enable System Actions",
            keywords: ["hide", "visibility"])
    ]

    private static let commands: [SettingsSearchEntry] = [
        .init(
            pane: .commands,
            keywords: ["custom", "script", "shell", "terminal"]),
        .init(
            .commandsCommands, "Enable Commands",
            keywords: ["hide", "visibility"]),
        .init(
            .commandsCustomCommands, "Enable custom commands",
            keywords: ["script", "shell"]),
        .init(
            .commandsCustomCommands, "Add Custom Command",
            keywords: ["new", "script", "shell", "shortcut"]),
        .init(
            .commandsCustomCommands, "Import Raycast Scripts",
            keywords: ["raycast", "script", "folder", "directory", "migrate"])
    ]

    private static let dictation: [SettingsSearchEntry] = [
        .init(pane: .dictation, keywords: ["speech", "voice", "transcription", "microphone"]),
        .init(.dictationDictation, "Enable Dictation"),
        .init(.dictationCommands, "Shortcut behavior"),
        .init(.dictationCommands, "Shortcut"),
        .init(.dictationCommands, "Play sounds", keywords: ["sound", "chime", "beep", "audio", "feedback"]),
        .init(.dictationModel, "Model"),
        .init(.dictationModel, "Engine", keywords: ["parakeet", "redux", "ultra", "qwen"]),
        .init(.dictationModel, "Language"),
        .init(.dictationMemory, "Release model from memory"),
        .init(.dictationOutput, "Microphone"),
        .init(.dictationOutput, "When finished"),
        .init(.dictationOutput, "Adapt capitalization", keywords: ["uppercase", "lowercase", "sentence"]),
        .init(.dictationOutput, "Insert while recording", keywords: ["live", "streaming", "chunk", "pause"])
    ]

    private static let fileSearch: [SettingsSearchEntry] = [
        .init(
            pane: .fileSearch,
            keywords: ["files", "folders", "find", "disk"]),
        .init(
            .fileSearchFileSearch, "Enable File Search",
            keywords: ["index", "disk", "show in launcher", "root search"]),
        .init(
            group: .fileSearchFullDiskAccess, "Full Disk Access",
            keywords: ["permission", "privacy", "grant", "fda"]),
        .init(
            group: .fileSearchIndex, "File index",
            keywords: ["rebuild", "refresh", "reindex", "indexed files"]),
        .init(
            group: .fileSearchCommands, "File search commands",
            keywords: ["shortcut", "launcher"]),
        .init(
            group: .fileSearchSearchScopes, "Search Scopes",
            keywords: ["folders", "locations", "home", "whole disk", "add folder"]),
        .init(
            group: .fileSearchIgnorePatterns, "Ignore Patterns",
            keywords: ["exclude", "glob", "node_modules", "skip", "ignore folder"])
    ]

    private static let fileTools: [SettingsSearchEntry] = [
        .init(
            pane: .fileTools,
            keywords: ["convert", "compress", "resize", "image", "heic", "jpeg", "png", "tangerine"]),
        .init(
            .fileToolsFileTools, "Enable File Tools",
            keywords: ["convert", "tab", "actions", "metadata"]),
        .init(
            .fileToolsFinder, "Tab in Finder",
            keywords: ["finder", "selection", "accessibility", "automation", "tab"]),
        .init(
            group: .fileToolsCommands, "File Tools commands",
            keywords: ["shortcut", "launcher"])
    ]

    private static let notes: [SettingsSearchEntry] = [
        .init(pane: .notes, keywords: ["markdown", "scratchpad", "floating"]),
        .init(
            .notesNotes, "Enable Notes",
            keywords: ["markdown", "scratchpad"]),
        .init(
            .notesOptions, "Render Markdown",
            keywords: ["markdown", "formatting", "preview", "raw", "source"]),
        .init(
            .notesOptions, "Show Formatting Bar",
            keywords: ["toolbar", "format bar", "buttons", "bold", "heading", "markdown"]),
        .init(
            .notesOptions, "Show in Menu Bar",
            keywords: ["status bar", "menu bar icon", "status item", "toolbar icon"]),
        .init(
            .notesOptions, "Notes Folder",
            keywords: ["location", "path", "dotfiles", "files", "markdown"]),
        .init(
            group: .notesCommands, "Notes commands",
            keywords: ["shortcut", "new note", "search notes"])
    ]

    private static let navigation: [SettingsSearchEntry] = [
        .init(
            pane: .navigation,
            keywords: ["window", "switch", "cmd tab", "menu bar", "focus", "raise"]),
        .init(
            .navigationNavigation, "Enable navigation",
            keywords: ["window switcher", "menu bar", "accessibility"]),
        .init(
            .navigationWindowSwitcher, "Shortcut",
            keywords: ["cmd tab", "command tab", "window switcher", "hotkey", "trigger"]),
        .init(
            .navigationWindowSwitcher, "Excluded Applications",
            keywords: ["cmd tab", "command tab", "window switcher", "hide", "exclude", "ignore"]),
        .init(
            .navigationMenuSearch, "Show Apple menu items",
            keywords: ["apple menu", "about this mac", "recent items", "sleep", "logo"]),
        .init(
            .navigationMenuSearch, "Excluded Applications",
            keywords: ["exclude", "password manager", "ignore", "privacy", "menu bar"])
    ]

    private static let windowManagement: [SettingsSearchEntry] = [
        .init(
            pane: .windowManagement,
            keywords: ["tile", "halves", "thirds", "maximize", "snap", "layouts", "arrangement"]),
        .init(
            .windowManagementWindowManagement, "Enable window management",
            keywords: ["tile", "accessibility"]),
        .init(
            .windowManagementOptions, "Cycling",
            keywords: ["repeat", "thirds", "halves", "displays", "monitor", "screens"]),
        .init(
            .windowManagementOptions, "Gap between windows",
            keywords: ["padding", "spacing", "margin", "points"]),
        .init(
            .windowManagementOptions, "Shortcut preset",
            keywords: ["rectangle", "magnet", "spectacle", "defaults", "import", "shortcuts"]),
        .init(
            group: .windowManagementOptions, "Window commands",
            keywords: ["shortcut", "alias", "left half", "maximize", "center"]),
        .init(
            group: .windowManagementLayoutCommands, "Layout and room commands",
            keywords: [
                "shortcut", "launcher", "create layout", "capture", "switch room", "create room"
            ]),
        .init(
            group: .windowManagementLayouts, "Window Layouts",
            keywords: [
                "layout", "arrangement", "workspace", "preset", "restore windows",
                "multi display", "monitor", "alias"
            ]),
        .init(
            .windowManagementLayouts, "Show layouts in launcher",
            keywords: ["hide", "visibility", "search"]),
        .init(
            .windowManagementLayouts, "New Layout",
            keywords: ["add", "create", "arrangement", "preset"]),
        .init(
            .windowManagementLayouts, "Create Layout from Current Windows",
            keywords: ["capture", "snapshot", "current", "save arrangement"]),
        .init(
            group: .windowManagementRooms, "Rooms",
            keywords: [
                "room", "project", "workspace", "tile", "focus", "columns", "grid", "stack",
                "hide other apps", "switch project", "alias"
            ]),
        .init(
            .windowManagementRooms, "Show rooms in launcher",
            keywords: ["hide", "visibility", "search"]),
        .init(
            .windowManagementRooms, "New Room",
            keywords: ["add", "create", "project", "windows"]),
        .init(
            group: .windowManagementCustomSizes, "Custom Sizes",
            keywords: ["custom", "size", "resize", "dimensions", "pixels", "points", "percent", "alias"]),
        .init(
            .windowManagementCustomSizes, "New Custom Size",
            keywords: ["add", "create", "resize", "window size"])
    ]

    private static let clipboard: [SettingsSearchEntry] = [
        .init(
            pane: .clipboard,
            keywords: ["paste", "history", "copy", "pasteboard"]),
        .init(
            .clipboardClipboard, "Enable Clipboard History",
            keywords: ["disable", "turn off", "monitor", "record", "privacy"]),
        .init(
            group: .clipboardCommands, "Clipboard commands",
            keywords: ["shortcut", "hotkey", "launcher", "paste", "browser"]),
        .init(
            .clipboardHistory, "Keep history for",
            keywords: ["retention", "delete", "privacy", "expire"]),
        .init(
            .clipboardHistory, "Search text in images and PDFs",
            keywords: ["OCR", "recognize", "scan", "screenshot", "background", "idle"]),
        .init(
            .clipboardHistory, "Default action",
            keywords: ["enter", "return", "paste", "copy", "primary"]),
        .init(
            group: .clipboardDisabledApplications, "Excluded Applications",
            keywords: ["exclude", "password manager", "ignore", "privacy"]),
        .init(
            .clipboardDisabledApplications, "Clear history",
            keywords: ["delete", "erase", "wipe"])
    ]

    private static let screenshot: [SettingsSearchEntry] = [
        .init(
            pane: .screenshot,
            keywords: ["capture", "screen", "snip", "grab", "shottr", "annotate", "record", "video"]),
        .init(
            group: .screenshotCommands, "Screenshot commands",
            keywords: ["shortcut", "hotkey", "capture"]),
        .init(
            .screenshotSaving, "Save Folder",
            keywords: ["desktop", "location", "directory", "png", "mov", "recording"]),
        .init(
            .screenshotSaving, "Recording Format",
            keywords: ["video", "screen recording", "mov", "mp4", "file type"])
    ]

    private static let emoji: [SettingsSearchEntry] = [
        .init(
            pane: .emoji,
            keywords: ["picker", "character", "unicode", "smiley"]),
        .init(
            group: .emojiCommands, "Emoji commands",
            keywords: ["shortcut", "hotkey", "launcher", "picker"]),
        .init(
            .emojiAppearance, "Emoji Skin Tone",
            keywords: ["colour", "color", "fitzpatrick", "default"]),
        .init(
            .emojiAppearance, "Column Count",
            keywords: ["columns", "density", "zoom", "six", "eight", "ten"])
    ]

    private static let permissions: [SettingsSearchEntry] = [
        .init(
            pane: .permissions,
            keywords: ["privacy", "tcc", "access", "grant"]),
        .init(
            .permissionsAccessibility, "Accessibility",
            keywords: ["paste", "keystrokes", "privacy", "grant"]),
        .init(
            .permissionsFullDiskAccess, "Full Disk Access",
            keywords: ["files", "folders", "uninstall", "leftovers", "privacy", "grant", "fda"]),
        .init(
            .permissionsMicrophone, "Microphone",
            keywords: ["dictation", "recording", "privacy", "grant"]),
        .init(
            .permissionsScreenRecording, "Screen Recording",
            keywords: ["screenshot", "capture", "window switcher", "previews", "privacy", "grant"])
    ]

    private static let backup: [SettingsSearchEntry] = [
        .init(
            pane: .backup,
            keywords: ["export", "import", "restore", "migrate", "raycast"]),
        .init(
            .backupExport, "Export Backup",
            keywords: ["save", "nanocast file", "archive"]),
        .init(
            .backupImport, "Backup File",
            keywords: ["restore", "choose", "nanocast file"]),
        .init(
            .backupImportFromRaycast, "Raycast Export",
            keywords: ["migrate", "rayconfig", "passphrase"]),
        .init(
            .backupSettingsFile, "Sync settings file",
            keywords: ["settings.json", "config", "json", "dotfiles", ".config", "edit"])
    ]

    private static let about: [SettingsSearchEntry] = [
        .init(
            pane: .about,
            keywords: ["version", "licence", "license", "credits"]),
        .init(
            .aboutAbout, "Check for Updates",
            keywords: ["version", "upgrade", "release"]),
        .init(
            group: .aboutLinks, "Links",
            keywords: ["github", "source", "issues"])
    ]
}
