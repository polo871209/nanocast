import AppKit
import SwiftUI

@MainActor
final class VolumeHUDController {
    private let settings: AppSettings
    private let presenter = HUDPresenter(
        anchor: .heightFraction(bottomFraction), dwell: Theme.Duration.volumeHUD,
        screen: { .underCursor })
    private let state = VolumeState(level: 0)

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show(level: Float32, muted: Bool) {
        let showing = presenter.isShowing
        state.level = VolumeLevel.clamped(Double(level))
        state.muted = muted
        if showing {
            presenter.extend()
        } else {
            let metrics = settings.interfaceSize.metrics
            presenter.show(
                VolumeHUDView(state: state).environment(\.metrics, metrics),
                size: CGSize(width: metrics.size.hudWidth, height: metrics.size.hudHeight))
        }
    }

    private static let bottomFraction: CGFloat = 0.12
}
