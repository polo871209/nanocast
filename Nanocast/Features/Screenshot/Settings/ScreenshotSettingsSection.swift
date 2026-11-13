import SwiftUI

struct ScreenshotSettingsSection: View {
    @Environment(ScreenshotCoordinator.self) private var screenshots
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section {
            LabeledContent {
                if settings.screenshotSaveFolder != nil {
                    Button("Use Default", action: screenshots.resetSaveFolder)
                }
                Button("Choose…", action: screenshots.chooseSaveFolder)
            } label: {
                SettingsRowTitle(.screenshotSaving, "Save Folder")
                Text((screenshots.saveFolder.path as NSString).abbreviatingWithTildeInPath)
            }
        } header: {
            SettingsSectionHeader(.screenshotSaving)
        } footer: {
            Text("⌘S in a capture saves a PNG here, and Return copies it instead.")
                .foregroundStyle(.secondary)
        }
    }
}
