import SwiftUI

struct FileToolsSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.fileToolsEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .fileToolsFileTools, title: "Enable File Tools",
                        subtitle: "Press Tab on a file in File Search, or run File Tools over Finder.")
                }
            } footer: {
                Text("Every job writes a new file beside the original. The original is never changed.")
                    .foregroundStyle(.secondary)
            }
            .settingsAnchor(.fileToolsFileTools)

            Section {
                Toggle(isOn: $settings.fileToolsFinderTab) {
                    SettingsRowTitle(.fileToolsFinder, "Tab in Finder")
                    Text("Tab on selected files in Finder opens File Tools. ⇧Tab keeps its Finder meaning.")
                }
                if settings.fileToolsFinderTab, !accessibilityTrusted {
                    LabeledContent {
                        Button("Open Accessibility Settings", action: Permissions.openAccessibilitySettings)
                    } label: {
                        Text("Tab in Finder needs Accessibility.")
                    }
                }
            } footer: {
                Text("The first read of the Finder selection asks to let Nanocast control Finder.")
                    .foregroundStyle(.secondary)
            }
            .settingsAnchor(.fileToolsFinder)
            .settingsEnabled(settings.fileToolsEnabled)

            FeatureCommandsSection(owner: .fileTools, anchor: .fileToolsCommands)
                .settingsEnabled(settings.fileToolsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.fileTools)
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                accessibilityTrusted = Permissions.isAccessibilityTrusted()
            }
        }
    }
}
