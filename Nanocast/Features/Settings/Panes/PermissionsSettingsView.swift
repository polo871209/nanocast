import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var fullDiskAccess = Permissions.hasFullDiskAccess()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: accessibilityStatus.symbol)
                                .accessibilityHidden(true)
                            Text(accessibilityStatus.title)
                        }
                        .foregroundStyle(accessibilityStatus.tint)
                        Button(accessibilityTrusted ? "Open…" : "Grant Access…") {
                            Permissions.openAccessibilitySettings()
                        }
                        .help("Opens Privacy & Security › Accessibility.")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        PermissionSettingsIcon(
                            path:
                                "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex"
                        )
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                            Text("Allows pasting and window management.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.permissionsAccessibility)
            }

            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: fullDiskAccessStatus.symbol)
                                .accessibilityHidden(true)
                            Text(fullDiskAccessStatus.title)
                        }
                        .foregroundStyle(fullDiskAccessStatus.tint)
                        Button(fullDiskAccess ? "Open…" : "Grant Access…") {
                            Permissions.openFullDiskAccessSettings()
                        }
                        .help("Opens Privacy & Security › Full Disk Access.")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: SettingsListMetrics.iconSize - Theme.Spacing.xs))
                            .frame(width: SettingsListMetrics.iconSize)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsFullDiskAccess, "Full Disk Access")
                            Text("Allows File Search and finding protected app leftovers.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.permissionsFullDiskAccess)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.permissions)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private var accessibilityStatus: (title: String, symbol: String, tint: Color) {
        grantStatus(accessibilityTrusted)
    }

    private var fullDiskAccessStatus: (title: String, symbol: String, tint: Color) {
        grantStatus(fullDiskAccess)
    }

    private func grantStatus(_ granted: Bool) -> (title: String, symbol: String, tint: Color) {
        granted
            ? ("Granted", "checkmark.circle.fill", .green)
            : ("Not granted", "exclamationmark.triangle.fill", .orange)
    }

    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        let diskAccess = Permissions.hasFullDiskAccess()
        if diskAccess != fullDiskAccess {
            fullDiskAccess = diskAccess
            core.fileIndexer.refreshAccess()
        }
    }
}

private struct PermissionSettingsIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: IconCache.icon(forFile: path))
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .id(IconCache.style.generation)
            .frame(
                width: SettingsListMetrics.iconSize,
                height: SettingsListMetrics.iconSize
            )
            .accessibilityHidden(true)
    }
}
