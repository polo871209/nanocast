import AVFoundation
import AppKit

@MainActor
final class CameraBubble {
    private let panel: LiveCapturePanel
    private let view: BubbleView

    var windowID: CGWindowID { CGWindowID(panel.windowNumber) }

    init(
        session: AVCaptureSession, inside area: CGRect, diameter: CGFloat?,
        resized: @escaping (CGFloat) -> Void
    ) {
        let side = BubbleView.clamped(diameter ?? min(area.width, area.height) * 0.25, inside: area)
        let margin = min(Theme.Spacing.lg, max(area.width - side, 0) / 2)
        panel = LiveCapturePanel(frame: CGRect(x: area.minX + margin, y: area.minY + margin, width: side, height: side))
        panel.hasShadow = true
        view = BubbleView(session: session, diameter: side, area: area, resized: resized)
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
    private static let resizeBand: CGFloat = 16
    private static let knobDiameter: CGFloat = 16

    var area: CGRect
    private let resized: (CGFloat) -> Void
    private let preview: AVCaptureVideoPreviewLayer
    private let video = CALayer()
    private let mask = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let knob = CAShapeLayer()
    private var drag: Drag?
    private var isHovered = false

    private enum Drag {
        case move(grab: CGPoint)
        case resize
    }

    static func clamped(_ diameter: CGFloat, inside area: CGRect) -> CGFloat {
        min(max(diameter, minimumDiameter), maximumDiameter, max(min(area.width, area.height), minimumDiameter))
    }

    init(session: AVCaptureSession, diameter: CGFloat, area: CGRect, resized: @escaping (CGFloat) -> Void) {
        self.area = area
        self.resized = resized
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        preview.videoGravity = .resizeAspectFill
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        video.mask = mask
        video.addSublayer(preview)
        ring.fillColor = nil
        ring.strokeColor = NSColor.white.cgColor
        ring.lineWidth = Self.ringWidth
        knob.fillColor = NSColor.white.cgColor
        knob.shadowOpacity = 0.4
        knob.shadowRadius = 2
        knob.shadowOffset = .zero
        knob.isHidden = true
        let root = CALayer()
        for layer in [video, ring, knob] { root.addSublayer(layer) }
        layer = root
        wantsLayer = true
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
        layOut()
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updatePointer(at: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer(at: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        knob.isHidden = drag == nil
        if drag == nil { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        if isOnRing(event) {
            drag = .resize
            Self.resizeCursor.set()
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
        knob.isHidden = !isHovered
        if isHovered { updatePointer(at: event) } else { NSCursor.arrow.set() }
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

    private static var resizeCursor: NSCursor { .frameResize(position: .bottomRight, directions: .all) }

    private func isOnRing(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        return hypot(point.x - bounds.midX, point.y - bounds.midY) > bounds.width / 2 - Self.resizeBand
    }

    private func updatePointer(at event: NSEvent) {
        guard drag == nil else { return }
        knob.isHidden = false
        (isOnRing(event) ? Self.resizeCursor : NSCursor.openHand).set()
    }

    private func resize(to diameter: CGFloat) {
        guard let window else { return }
        let side = Self.clamped(diameter, inside: area)
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        place(CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
        resized(side)
    }

    private func layOut() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let circle = CGPath(ellipseIn: bounds, transform: nil)
        layer?.frame = bounds
        video.frame = bounds
        preview.frame = bounds
        mask.path = circle
        let inset = Self.ringWidth / 2
        ring.path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
        let radius = bounds.width / 2 - Self.knobDiameter / 2 - 1
        let knobCenter = CGPoint(x: bounds.midX + radius * cos(.pi / 4), y: bounds.midY - radius * sin(.pi / 4))
        knob.path = CGPath(
            ellipseIn: CGRect(
                x: knobCenter.x - Self.knobDiameter / 2, y: knobCenter.y - Self.knobDiameter / 2,
                width: Self.knobDiameter, height: Self.knobDiameter), transform: nil)
        CATransaction.commit()
    }
}
