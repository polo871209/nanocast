import SwiftUI

struct MenuBarLabel: View {
    let appName: String

    var body: some View {
        Image("MenuBarIcon")
            .accessibilityLabel(appName)
    }
}

struct MenuBarMenu: View {
    let appName: String

    var body: some View {
        Button("Open \(appName)") {
            AppCore.shared.paletteCoordinator.showPalette(mode: .launcher)
        }
        if AppCore.shared.settings.clipboardEnabled {
            Button("Clipboard History") {
                AppCore.shared.paletteCoordinator.showPalette(mode: .clipboard)
            }
        }
        Divider()
        Button("Check for Updates…") { AppCore.shared.updateCoordinator.checkForUpdates() }
        Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit \(appName)") { NSApp.terminate(nil) }
    }
}
