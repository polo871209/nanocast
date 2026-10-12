import SwiftUI

struct ScreenshotSettingsView: View {
    @Environment(ScreenshotCoordinator.self) private var screenshots
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            FeatureCommandsSection(owner: .screenshot, anchor: .screenshotCommands)

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
                Text("⌘S in a capture saves a PNG here. Return copies it instead.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.screenshot)
    }
}
