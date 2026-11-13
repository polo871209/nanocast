import SwiftUI

struct ScreenshotSettingsView: View {
    @Environment(ScreenshotCoordinator.self) private var screenshots
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
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
                Picker(selection: $settings.screenshotRecordingFormat) {
                    ForEach(ScreenRecordingFormat.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.screenshotSaving, "Recording Format")
                }
            } header: {
                SettingsSectionHeader(.screenshotSaving)
            } footer: {
                Text("⌘S in a capture saves a PNG here, and Return copies it instead. ⌘R records the screen to a file here.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.screenshot)
    }
}
