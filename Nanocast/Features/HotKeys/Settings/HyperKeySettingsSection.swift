import SwiftUI

struct HyperKeySettingsSection: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var diagnostics: HyperKeyDiagnostics?
    @State private var takeover: HyperKeyDiagnostics.Takeover?

    private var manager: HyperKeyManager { core.hyperKey }

    private var hyperGlyphs: String { settings.hyperKeyIncludesShift ? "⌃⌥⇧⌘" : "⌃⌥⌘" }

    private var hyperKeySelection: Binding<HyperKeyPhysicalKey> {
        Binding(
            get: { settings.hyperKey },
            set: { key in
                guard key != settings.hyperKey else { return }
                settings.hyperKey = key
                settings.hyperKeyQuickPress = .none
                if key != .none { Permissions.ensureAccessibility() }
            })
    }

    private var hyperSubtitle: String {
        guard settings.hyperKey != .none else {
            return "Use one key to hold \(hyperGlyphs) together."
        }
        return "\(settings.hyperKey.title) sends \(hyperGlyphs), shown as ✦ in shortcuts."
    }

    var body: some View {
        @Bindable var settings = settings
        Section {
            Picker(selection: hyperKeySelection) {
                ForEach(HyperKeyPhysicalKey.allCases) { key in
                    Text(key.title).tag(key)
                }
            } label: {
                SettingsRowTitle(.generalHyperKey, "Hyper Key")
                Text(hyperSubtitle)
            }

            if settings.hyperKey != .none {
                HyperKeyStatusRow(
                    status: manager.status, takeover: takeover, isShowingDiagnostics: diagnostics != nil
                ) {
                    diagnostics = diagnostics == nil ? manager.diagnostics() : nil
                    takeover = manager.takeover()
                }
            }

            if settings.hyperKey.hasOriginalFunction {
                Picker(selection: $settings.hyperKeyQuickPress) {
                    Text("Does Nothing").tag(HyperKeyQuickPress.none)
                    if let original = settings.hyperKey.quickPressOriginalTitle {
                        Text(original).tag(HyperKeyQuickPress.originalKey)
                    }
                    Text("Trigger Escape").tag(HyperKeyQuickPress.escape)
                } label: {
                    SettingsRowTitle(.generalHyperKey, "Quick Press")
                    Text("When you press and release \(settings.hyperKey.title) on its own.")
                }
            }

            Toggle(isOn: $settings.hyperKeyIncludesShift) {
                SettingsRowTitle(.generalHyperKey, "Include Shift (⇧)")
            }
            .settingsEnabled(settings.hyperKey != .none)

            if settings.hyperKey.supportsSecureInputCompatibility {
                Toggle(isOn: $settings.hyperKeySecureInputCompatibility) {
                    SettingsRowTitle(.generalHyperKey, "Secure Input Compatibility")
                    Text(
                        """
                        Nanocast's Hyper shortcuts also work in password fields and secure terminals, \
                        where Right Control (⌃) with the same key triggers them. \
                        While on, Right Control (⌃) acts as the Hyper Key too.
                        """)
                }
            }
        } header: {
            SettingsSectionHeader(.generalHyperKey)
        }
        .onAppear { takeover = manager.takeover() }
        .onChange(of: manager.status) {
            takeover = manager.takeover()
            if diagnostics != nil { diagnostics = manager.diagnostics() }
        }

        if let diagnostics, settings.hyperKey != .none {
            HyperKeyDiagnosticsSection(
                diagnostics: diagnostics,
                refresh: {
                    self.diagnostics = manager.diagnostics()
                    takeover = self.diagnostics?.takeover
                },
                restart: {
                    manager.restart()
                    self.diagnostics = manager.diagnostics()
                    takeover = self.diagnostics?.takeover
                })
        }
    }

    private struct HyperKeyStatusRow: View {
        let status: HyperKeyManager.Status
        let takeover: HyperKeyDiagnostics.Takeover?
        let isShowingDiagnostics: Bool
        let toggleDiagnostics: () -> Void

        var body: some View {
            SettingsRow(title: "Status", subtitle: detail, subtitleLineLimit: 3) {
                HStack(spacing: Theme.Spacing.sm) {
                    ColorDot(color: tint)
                    Text(title).foregroundStyle(.secondary)
                    if status == .needsAccessibility {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                    }
                    Button(
                        isShowingDiagnostics ? "Hide Diagnostics" : "Diagnostics…", action: toggleDiagnostics)
                }
            }
        }

        private var title: String {
            if takeover != nil { return "Taken Over" }
            switch status {
            case .off: return "Off"
            case .active: return "Active"
            case .needsAccessibility: return "Needs Accessibility"
            case .blocked: return "Blocked"
            case .remapUnavailable: return "Unavailable"
            case .paused: return "Paused"
            }
        }

        private var detail: String? {
            if let takeover { return describe(takeover) }
            switch status {
            case .blocked(let appName):
                return "\(appName) runs its own Hyper Key. Quit it to use this one."
            case .remapUnavailable: return "macOS refused to remap the keyboard."
            case .paused:
                return "The key works normally during sleep, screen lock or user switching."
            case .off, .active, .needsAccessibility: return nil
            }
        }

        private var tint: Color {
            if takeover != nil { return Theme.Colors.destructive }
            switch status {
            case .active: return Theme.Colors.success
            case .needsAccessibility, .paused: return Theme.Colors.warning
            case .off, .blocked, .remapUnavailable: return Theme.Colors.destructive
            }
        }

        private func describe(_ takeover: HyperKeyDiagnostics.Takeover) -> String {
            let keyboards = takeover.keyboards.formatted(.list(type: .and))
            var sentences = ["Another app now remaps Caps Lock on \(keyboards)."]
            if !takeover.likelyApps.isEmpty {
                sentences.append(
                    "Probably \(takeover.likelyApps.formatted(.list(type: .or))).")
            }
            return sentences.joined(separator: " ")
        }
    }
}
