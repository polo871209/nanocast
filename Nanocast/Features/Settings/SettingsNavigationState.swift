import Observation

@MainActor
@Observable
final class SettingsNavigationState {
    private var history: SettingsHistory
    private var requests = 0

    init(tab: SettingsTab) {
        history = SettingsHistory(current: tab)
    }

    var tab: SettingsTab { history.current }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    private(set) var scrollRequest: SettingsScrollRequest?
    private(set) var flashing: SettingsTarget?

    func select(_ tab: SettingsTab, revealing target: SettingsTarget? = nil) {
        history.select(tab)
        flashing = nil
        guard let target else { return }
        requests += 1
        scrollRequest = SettingsScrollRequest(target: target, token: requests)
    }

    func beginFlash(_ target: SettingsTarget) {
        flashing = target
    }

    func endFlash(_ target: SettingsTarget) {
        guard flashing == target else { return }
        flashing = nil
    }

    func clear(_ request: SettingsScrollRequest) {
        guard scrollRequest == request else { return }
        scrollRequest = nil
    }

    func goBack() { history.goBack() }
    func goForward() { history.goForward() }
}
