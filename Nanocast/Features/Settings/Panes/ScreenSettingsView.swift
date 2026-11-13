import SwiftUI

struct ScreenSettingsView: View {
    var body: some View {
        Form {
            FeatureCommandsSection(owner: .screen, anchor: .screenCommands)
            ScreenshotSettingsSection()
            ScreenRecordingSettingsSections()
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.screen)
    }
}
