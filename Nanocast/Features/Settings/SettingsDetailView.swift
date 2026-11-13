import SwiftUI

struct SettingsDetailView: View {
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        // Not a `TabView`: `NSTabView` re-hosts on selection and breaks the recorder.
        Group {
            switch navigation.tab {
            case .general: GeneralSettingsView()
            case .applications: ApplicationsSettingsView()
            case .systemSettings: SystemSettingsSettingsView()
            case .systemActions: SystemActionsSettingsView()
            case .commands: CommandsSettingsView()
            case .fileSearch: FileSearchSettingsView()
            case .notes: NotesSettingsView()
            case .navigation: NavigationSettingsView()
            case .windowManagement: WindowManagementSettingsView()
            case .clipboard: ClipboardSettingsView()
            case .screenshot: ScreenshotSettingsView()
            case .emoji: EmojiSettingsView()
            case .permissions: PermissionsSettingsView()
            case .backup: BackupSettingsView()
            case .about: AboutView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shortcutRecorderPopoverHost()
    }
}
