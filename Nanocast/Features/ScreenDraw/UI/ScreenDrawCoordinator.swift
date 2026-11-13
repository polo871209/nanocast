import AppKit

@MainActor
final class ScreenDrawCoordinator {
    private unowned let core: AppCore
    private var drawing: ScreenDrawController?

    init(core: AppCore) {
        self.core = core
    }

    var canvasWindows: [CGWindowID] { drawing?.canvasWindows ?? [] }

    func toggle() {
        guard drawing == nil else { return end() }
        guard !core.isShowingDialog else { return }
        if core.paletteCoordinator.isVisible { core.paletteCoordinator.hidePalette(restoreFocus: false) }
        let controller = ScreenDrawController(metrics: core.settings.interfaceSize.metrics) { [weak self] in
            self?.end()
        }
        drawing = controller
        controller.show()
        core.screenRecordingCoordinator.drawingChanged()
    }

    private func end() {
        guard let drawing else { return }
        self.drawing = nil
        drawing.close()
        core.screenRecordingCoordinator.drawingChanged()
    }
}
