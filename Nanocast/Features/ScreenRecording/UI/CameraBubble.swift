import AVFoundation
import AppKit

@MainActor
final class CameraBubble {
    private let panel: LiveCapturePanel
    private let view: BubbleView

    var windowID: CGWindowID { CGWindowID(panel.windowNumber) }

    init(session: AVCaptureSession, inside area: CGRect) {
        let diameter = BubbleView.clamped(min(area.width, area.height) * 0.25, inside: area)
        let margin = min(Theme.Spacing.lg, max(area.width - diameter, 0) / 2)
        panel = LiveCapturePanel(
            frame: CGRect(x: area.minX + margin, y: area.minY + margin, width: diameter, height: diameter))
        panel.hasShadow = true
        view = BubbleView(session: session, diameter: diameter, area: area)
        panel.contentView = view
    }

    func show() {
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
    }

    func follow(_ area: CGRect, from previous: CGRect) {
        view.area = area
        var frame = panel.frame.offsetBy(dx: area.minX - previous.minX, dy: area.minY - previous.minY)
        let side = BubbleView.clamped(frame.width, inside: area)
        frame.size = CGSize(width: side, height: side)
        view.place(frame)
    }
}

private final class BubbleView: NSView {
    private static let minimumDiameter: CGFloat = 64
    private static let maximumDiameter: CGFloat = 480
    private static let ringWidth: CGFloat = 3
    private static let resizeBand: CGFloat = 14

    var area: CGRect
    private let preview: AVCaptureVideoPreviewLayer
    private let mask = CAShapeLayer()
    private let ring = CAShapeLayer()
    private var drag: Drag?

    private enum Drag {
        case move(grab: CGPoint)
        case resize
    }

    static func clamped(_ diameter: CGFloat, inside area: CGRect) -> CGFloat {
        min(max(diameter, minimumDiameter), maximumDiameter, max(min(area.width, area.height), minimumDiameter))
    }

    init(session: AVCaptureSession, diameter: CGFloat, area: CGRect) {
        self.area = area
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        preview.videoGravity = .resizeAspectFill
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        ring.fillColor = nil
        ring.strokeColor = NSColor.white.cgColor
        ring.lineWidth = Self.ringWidth * 2
        let bubble = CALayer()
        bubble.mask = mask
        bubble.addSublayer(preview)
        bubble.addSublayer(ring)
        layer = bubble
        wantsLayer = true
        layOut()
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if hypot(point.x - center.x, point.y - center.y) > bounds.width / 2 - Self.resizeBand {
            drag = .resize
            NSCursor.frameResize(position: .bottomRight, directions: .all).set()
        } else {
            drag = .move(grab: event.locationInWindow)
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let window else { return }
        let pointer = NSEvent.mouseLocation
        switch drag {
        case .move(let grab):
            var frame = window.frame
            frame.origin = CGPoint(x: pointer.x - grab.x, y: pointer.y - grab.y)
            place(frame)
        case .resize:
            let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
            resize(to: 2 * hypot(pointer.x - center.x, pointer.y - center.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
        NSCursor.openHand.set()
    }

    override func scrollWheel(with event: NSEvent) {
        resize(to: bounds.width + event.scrollingDeltaY)
    }

    override func magnify(with event: NSEvent) {
        resize(to: bounds.width * (1 + event.magnification))
    }

    func place(_ frame: CGRect) {
        guard let window else { return }
        var frame = frame
        frame.origin.x = min(max(frame.minX, area.minX), area.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, area.minY), area.maxY - frame.height)
        window.setFrame(frame, display: true)
        layOut()
        window.invalidateShadow()
    }

    private func resize(to diameter: CGFloat) {
        guard let window else { return }
        let side = Self.clamped(diameter, inside: area)
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        place(CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
    }

    private func layOut() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let circle = CGPath(ellipseIn: bounds, transform: nil)
        layer?.frame = bounds
        preview.frame = bounds
        mask.path = circle
        ring.path = circle
        CATransaction.commit()
        window?.invalidateCursorRects(for: self)
    }
}
