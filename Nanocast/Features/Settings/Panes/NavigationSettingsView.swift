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
                        subtitle: "Switch windows and search menu bar items.")
                }
            }
            .settingsAnchor(.navigationNavigation)

            FeatureCommandsSection(
                owner: .navigation, anchor: .navigationCommands,
                excluding: [.searchMenuItems]
            )
            .settingsEnabled(settings.navigationEnabled)

            Section {
                if let entry = CommandCatalog.entry(for: .searchMenuItems) {
                    FeatureCommandRow(entry: entry)
                }

                Toggle(isOn: $settings.menuSearchShowsAppleMenu) {
                    SettingsRowTitle(.navigationMenuSearch, "Show Apple menu items")
                }

                SettingsRow(
                    title: "Excluded Applications",
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
