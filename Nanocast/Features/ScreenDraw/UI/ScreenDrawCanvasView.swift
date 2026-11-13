import AppKit

final class ScreenDrawCanvasView: NSView {
    private let session: ScreenDrawSession
    private let changed: () -> Void
    private let marksLayer = AnnotationLayer()
    private let globalFrame: CGRect

    /// `globalFrame` is the screen in top-left global points, the space the board's marks live in.
    init(
        globalFrame: CGRect, scale: CGFloat, session: ScreenDrawSession, painter: AnnotationPainter,
        changed: @escaping () -> Void
    ) {
        self.session = session
        self.changed = changed
        self.globalFrame = globalFrame
        super.init(frame: CGRect(origin: .zero, size: globalFrame.size))
        wantsLayer = true
        marksLayer.painter = painter
        marksLayer.contentsScale = scale
        marksLayer.contentsGravity = .resize
        marksLayer.needsDisplayOnBoundsChange = true
        layer?.addSublayer(marksLayer)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        session.press(at: location(of: event))
        changed()
    }

    override func mouseDragged(with event: NSEvent) {
        session.drag(to: location(of: event), constrained: event.modifierFlags.contains(.shift))
        changed()
    }

    override func mouseUp(with event: NSEvent) {
        session.release()
        changed()
    }

    func render() {
        let metrics = session.metrics
        let marks = session.board.visible.filter {
            AnnotationGeometry.frame(of: $0, metrics: metrics).intersects(globalFrame)
        }
        let region = marks.reduce(CGRect.null) { $0.union(AnnotationGeometry.frame(of: $1, metrics: metrics)) }
            .insetBy(dx: -2, dy: -2).intersection(globalFrame).integral
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        marksLayer.isHidden = region.isEmpty
        marksLayer.frame = region.isEmpty ? .zero : region.offsetBy(dx: -globalFrame.minX, dy: -globalFrame.minY)
        marksLayer.content = AnnotationLayer.Content(marks: region.isEmpty ? [] : marks, region: region)
        CATransaction.commit()
    }

    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x + globalFrame.minX, y: point.y + globalFrame.minY)
    }
}
