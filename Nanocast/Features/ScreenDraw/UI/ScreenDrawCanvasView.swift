import AppKit
import SwiftUI

final class ScreenDrawCanvasView: NSView {
    private let session: ScreenDrawSession
    private let changed: () -> Void
    private let endTextEverywhere: () -> Void
    private let marksLayer = AnnotationLayer()
    private let globalFrame: CGRect
    private var textEditor: TextEditOverlay?

    /// `globalFrame` is the screen in top-left global points, the space the board's marks live in.
    init(
        globalFrame: CGRect, scale: CGFloat, session: ScreenDrawSession, painter: AnnotationPainter,
        changed: @escaping () -> Void, endTextEverywhere: @escaping () -> Void
    ) {
        self.session = session
        self.changed = changed
        self.endTextEverywhere = endTextEverywhere
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
        cursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        cursor.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if session.board.editing != nil { return endTextEverywhere() }
        session.press(at: location(of: event))
        beginTextEdit()
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
        marksLayer.content = AnnotationLayer.Content(
            marks: region.isEmpty ? [] : marks, region: region, hiddenText: session.board.editing?.id)
        CATransaction.commit()
        restyleTextEditor()
    }

    func endTextEdit() {
        guard let textEditor else { return }
        self.textEditor = nil
        textEditor.removeFromSuperview()
        window?.makeFirstResponder(nil)
    }

    /// The panel has no Edit menu to send these, so the canvas hands them to the text view itself.
    func performTextCommand(_ key: String, shift: Bool) -> Bool {
        guard let textEditor else { return false }
        switch (key, shift) {
        case ("z", false): textEditor.undoManager?.undo()
        case ("z", true): textEditor.undoManager?.redo()
        case ("x", false): textEditor.cut(nil)
        case ("c", false): textEditor.copy(nil)
        case ("v", false): textEditor.paste(nil)
        case ("a", false): textEditor.selectAll(nil)
        default: return false
        }
        return true
    }

    private var cursor: NSCursor { session.tool == .text ? .iBeam : .crosshair }

    private func beginTextEdit() {
        guard textEditor == nil, let editing = session.board.editing, case .text(let text, _) = editing.shape else {
            return
        }
        let editor = TextEditOverlay(
            text: text, font: font(editing.style), color: color(editing.style), origin: localOrigin(of: editing),
            changed: { [weak self] in
                self?.session.updateText($0)
                self?.changed()
            },
            finished: { [weak self] in self?.endTextEverywhere() })
        addSubview(editor)
        textEditor = editor
        window?.makeFirstResponder(editor)
    }

    private func restyleTextEditor() {
        guard let textEditor, let editing = session.board.editing else { return }
        textEditor.restyle(font: font(editing.style), color: color(editing.style))
    }

    private func font(_ style: AnnotationStyle) -> NSFont {
        AnnotationText.font(size: session.metrics.textSize(style.textSize), face: ScreenDrawSession.textFace)
    }

    private func color(_ style: AnnotationStyle) -> NSColor {
        NSColor(AnnotationAppearance.color(style.ink))
    }

    private func localOrigin(of annotation: Annotation) -> CGPoint {
        guard case .text(_, let origin) = annotation.shape else { return .zero }
        return CGPoint(x: origin.x - globalFrame.minX, y: origin.y - globalFrame.minY)
    }

    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x + globalFrame.minX, y: point.y + globalFrame.minY)
    }
}
