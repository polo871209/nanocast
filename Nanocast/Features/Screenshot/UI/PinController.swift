import AppKit

@MainActor
final class PinController {
    private var panels: [PinPanel] = []
    private let deliver: (CGImage, CGFloat, _ saving: Bool) -> Void

    init(deliver: @escaping (CGImage, CGFloat, _ saving: Bool) -> Void) {
        self.deliver = deliver
    }

    func pin(_ crop: CGImage, scale: CGFloat, at frame: CGRect) {
        guard let image = ScreenshotRenderer.ownCopy(of: crop) else { return }
        weak var panel: PinPanel?
        let view = PinView(image: image, scale: scale) { [weak self] action in
            guard let self, let panel else { return }
            switch action {
            case .copy: deliver(image, scale, false)
            case .save: deliver(image, scale, true)
            case .close: close(panel)
            }
        }
        let opened = PinPanel(frame: frame, content: view)
        panel = opened
        panels.append(opened)
        opened.makeKeyAndOrderFront(nil)
        opened.makeFirstResponder(view)
    }

    private func close(_ panel: PinPanel) {
        panel.orderOut(nil)
        panel.contentView = nil
        panels.removeAll { $0 === panel }
    }
}
