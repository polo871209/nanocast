import SwiftUI

@MainActor
final class OnboardingCoordinator {
    private let window: AppWindowController
    private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: "Welcome to Nanocast", contentSize: OnboardingView.initialSize,
            activation: core.activationPolicy)
    }

    func fit(height: CGFloat) {
        window.fitContent(width: OnboardingView.width, height: height)
    }

    func showOnboarding() {
        window.show {
            OnboardingView()
                .environment(self.core)
                .environment(self.core.settings)
                .environment(self.core.hotKeys)
        }
    }

    func finishOnboarding() {
        window.close()
        core.paletteCoordinator.showPalette(mode: .launcher)
    }

    func focusExisting() -> Bool {
        window.focus()
    }
}
