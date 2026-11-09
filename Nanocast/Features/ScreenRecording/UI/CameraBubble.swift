import AVFoundation
import AppKit

@MainActor
final class CameraBubble {
    private let panel: LiveCapturePanel

    var windowID: CGWindowID { CGWindowID(panel.windowNumber) }

    init(session: AVCaptureSession, inside area: CGRect) {
        let diameter = min(max(min(area.width, area.height) * 0.25, 80), 220)
        let margin = min(Theme.Spacing.lg, max(area.width - diameter, 0) / 2)
        panel = LiveCapturePanel(
            frame: CGRect(x: area.minX + margin, y: area.minY + margin, width: diameter, height: diameter))
        panel.hasShadow = true
        panel.contentView = BubbleView(session: session, diameter: diameter, area: area)
    }

    func show() {
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}

private final class BubbleView: NSView {
    private let area: CGRect
    private var grab: CGPoint?

    init(session: AVCaptureSession, diameter: CGFloat, area: CGRect) {
        self.area = area
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        let circle = CGPath(ellipseIn: bounds, transform: nil)
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        let mask = CAShapeLayer()
        mask.path = circle
        let ring = CAShapeLayer()
        ring.path = circle
        ring.fillColor = nil
        ring.strokeColor = NSColor.white.cgColor
        ring.lineWidth = 6
        let bubble = CALayer()
        bubble.frame = bounds
        bubble.mask = mask
        bubble.addSublayer(preview)
        bubble.addSublayer(ring)
        layer = bubble
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        grab = event.locationInWindow
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grab, let window else { return }
        let pointer = NSEvent.mouseLocation
        var frame = window.frame
        frame.origin = CGPoint(
            x: min(max(pointer.x - grab.x, area.minX), area.maxX - frame.width),
            y: min(max(pointer.y - grab.y, area.minY), area.maxY - frame.height))
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        grab = nil
        NSCursor.openHand.set()
    }
}
