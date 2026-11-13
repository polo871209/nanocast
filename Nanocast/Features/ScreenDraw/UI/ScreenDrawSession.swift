import Foundation

@MainActor
@Observable
final class ScreenDrawSession {
    static let textFace = AnnotationText.Face.rounded

    private(set) var tool = DrawTool.pen
    private(set) var ink = AnnotationStyle.Ink.red
    private(set) var canUndo = false
    private(set) var hasMarks = false
    @ObservationIgnored private(set) var board = AnnotationBoard()
    @ObservationIgnored let metrics = AnnotationAppearance.metrics(scale: 1, face: textFace)

    var style: AnnotationStyle {
        var style = AnnotationStyle()
        style.ink = ink
        style.highlighterFreehand = true
        return style
    }

    func choose(_ tool: DrawTool) {
        self.tool = tool
    }

    func pick(_ ink: AnnotationStyle.Ink) {
        self.ink = ink
        board.restyleEditing(style)
        if tool == .eraser { tool = .pen }
    }

    func press(at point: CGPoint) {
        switch tool.markup {
        case nil: board.beginErasing(at: point, metrics: metrics)
        case .text: beginText(at: point)
        case let markup?: board.beginStroke(at: point, tool: markup, style: style)
        }
    }

    func drag(to point: CGPoint, constrained: Bool) {
        board.drag(to: point, constrained: constrained, metrics: metrics)
    }

    func release() {
        board.release()
        publish()
    }

    func updateText(_ text: String) {
        board.updateEditing(text)
    }

    func endText() {
        board.endEditing()
        publish()
    }

    func undo() {
        board.undo()
        publish()
    }

    func redo() {
        board.redo()
        publish()
    }

    func clear() {
        board.clear()
        publish()
    }

    private func beginText(at point: CGPoint) {
        guard !board.editText(at: point, metrics: metrics) else { return }
        let lineHeight = metrics.measureText(" ", metrics.textSize(style.textSize)).height
        board.beginText(at: CGPoint(x: point.x, y: point.y - lineHeight / 2), style: style)
    }

    private func publish() {
        canUndo = board.canUndo
        hasMarks = !board.annotations.isEmpty
    }
}
