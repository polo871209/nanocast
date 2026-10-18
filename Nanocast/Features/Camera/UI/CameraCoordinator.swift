import AppKit
import SwiftUI

@MainActor
@Observable
final class CameraCoordinator {
    private(set) var feed: CameraSession.Feed = .noCamera
    private(set) var canSwitchCamera = false
    var mirrored = true

    @ObservationIgnored private let session = CameraSession()
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var panel: CameraPanel?
    @ObservationIgnored private var opening = false

    init(core: AppCore) {
        self.core = core
    }

    func show() async {
        if let panel {
            panel.makeKey()
            return
        }
        guard !opening else { return }
        opening = true
        defer { opening = false }
        feed = await session.start()
        canSwitchCamera = session.hasMultipleDevices
        present()
    }

    func close() {
        guard let closing = panel else { return }
        panel = nil
        closing.onAction = nil
        closing.fadeOut(duration: Theme.Duration.exit) { [weak self] in
            guard let self, !opening else { return }
            session.stop()
        }
    }

    func switchCamera() {
        Task { await session.switchToNextDevice() }
    }

    func takePhoto() {
        guard case .live = feed else { return }
        let mirrored = mirrored
        Task {
            let png = await session.capturePhoto(mirrored: mirrored)
            close()
            guard let png else {
                core.showMessage("Couldn't take the photo", tone: .danger)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
            core.showMessage("Photo copied")
        }
    }

    private func present() {
        let hosting = NSHostingView(rootView: CameraView(coordinator: self))
        hosting.setFrameSize(hosting.fittingSize)
        let panel = CameraPanel(content: hosting)
        panel.onAction = { [weak self] action in
            guard let self else { return }
            if action == .primary { takePhoto() } else { close() }
        }
        self.panel = panel
        panel.centerOnCursorScreen()
        panel.fadeIn(duration: Theme.Duration.enter) {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }
}
