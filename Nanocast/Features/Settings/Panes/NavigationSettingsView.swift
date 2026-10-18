import SwiftUI

struct NavigationSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.navigationEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .navigationNavigation, title: "Enable navigation",
                        subtitle: "Switch windows from a shortcut, and search menu bar items.")
                }
            }
            .settingsAnchor(.navigationNavigation)

            Section {
                SettingsRow(
                    title: "Shortcut",
                    subtitle: "Hold its modifiers and press the key to step. Delete resets it to ⌘Tab.",
                    anchor: .navigationWindowSwitcher
                ) {
                    ShortcutRecorder(action: .windowSwitcher)
                }

                SettingsRow(
                    title: "Excluded Applications",
                    subtitle: "Their windows never appear in the switcher.",
                    anchor: .navigationWindowSwitcher
                ) {
                    EmptyView()
                }

                DisabledApplicationsList(bundleIDs: $settings.windowSwitcherExcludedApps)
            } header: {
                SettingsSectionHeader(.navigationWindowSwitcher)
            }
            .settingsEnabled(settings.navigationEnabled)

            Section {
                if let entry = CommandCatalog.entry(for: .searchMenuItems) {
                    FeatureCommandRow(entry: entry)
                }

                Toggle(isOn: $settings.menuSearchShowsAppleMenu) {
                    SettingsRowTitle(.navigationMenuSearch, "Show Apple menu items")
                }

                SettingsRow(
                    title: "Disabled Applications",
                    subtitle: "Their menus are never searched.",
                    anchor: .navigationMenuSearch
                ) {
                    EmptyView()
                }

                DisabledApplicationsList(bundleIDs: $settings.menuSearchDisabledApps)
            } header: {
                SettingsSectionHeader(.navigationMenuSearch)
            }
            .settingsEnabled(settings.navigationEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.navigation)
    }
}
