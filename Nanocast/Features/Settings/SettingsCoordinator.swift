import SwiftUI

@MainActor
final class SettingsCoordinator {
    private let window: AppWindowController
    private unowned let core: AppCore
    private weak var navigation: SettingsNavigationState?
    private weak var editorPresenter: SettingsEditorPresenter?

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: "Settings", contentSize: Theme.Size.settingsWindow, resizable: true,
            autosaveName: "SettingsWindow", activation: core.activationPolicy)
    }

    func showSettings(tab: SettingsTab? = nil, revealing target: SettingsTarget? = nil) {
        if window.focus() {
            if let tab { navigation?.select(tab, revealing: target) }
            return
        }
        let navigation = SettingsNavigationState(tab: tab ?? .general)
        navigation.select(navigation.tab, revealing: target)
        let editorPresenter = SettingsEditorPresenter(core: core, navigation: navigation)
        self.navigation = navigation
        self.editorPresenter = editorPresenter
        let hosting = NSHostingController(
            rootView: SettingsRootView().settingsEnvironment(
                core: core, navigation: navigation, editorPresenter: editorPresenter))
        hosting.sizingOptions = []
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.show(chrome: SettingsWindowChrome()) { hosting }
        editorPresenter.attach(to: hosting.view.window)
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func showBackupSettings() {
        showSettings(tab: .backup)
    }

    func closeSettings() {
        editorPresenter?.dismissAll()
        window.close()
    }

    func focusExisting() -> Bool {
        window.focus()
    }
}
