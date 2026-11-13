import Foundation

@MainActor
@Observable
final class ScreenDrawSession {
    private(set) var tool = DrawTool.pen
    private(set) var ink = AnnotationStyle.Ink.red
    private(set) var canUndo = false
    private(set) var hasMarks = false
    @ObservationIgnored private(set) var board = AnnotationBoard()
    @ObservationIgnored let metrics = AnnotationAppearance.metrics(scale: 1)

    func choose(_ tool: DrawTool) {
        self.tool = tool
    }

    func pick(_ ink: AnnotationStyle.Ink) {
        self.ink = ink
        if tool == .eraser { tool = .pen }
    }

    func press(at point: CGPoint) {
        guard let markup = tool.markup else { return board.beginErasing(at: point, metrics: metrics) }
        var style = AnnotationStyle()
        style.ink = ink
        style.highlighterFreehand = true
        board.beginStroke(at: point, tool: markup, style: style)
    }

    func drag(to point: CGPoint, constrained: Bool) {
        board.drag(to: point, constrained: constrained, metrics: metrics)
    }

    func release() {
        board.release()
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

    private func publish() {
        canUndo = board.canUndo
        hasMarks = !board.annotations.isEmpty
    }
}
