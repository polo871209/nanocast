import CoreGraphics
import Foundation

@main
@MainActor
struct ScreenDrawTests {
    static var failures = 0

    static let metrics = AnnotationMetrics(
        scale: 1,
        points: AnnotationMetrics.Points(
            strokes: [1, 2, 4, 8], highlighters: [6, 10, 16, 24], textSizes: [10, 20, 30],
            brushes: [10, 20, 40], stepInset: 5, mosaicBlock: 10, blurBlock: 4, hitSlop: 4, dragSlop: 3,
            selectionOutset: 4, handleReach: 6),
        measureText: { text, size in CGSize(width: CGFloat(text.count) * size / 2, height: size) })

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual != expected else { return }
        failures += 1
        print("FAIL: \(message)\n  expected \(expected)\n  actual   \(actual)")
    }

    static func main() {
        keys()
        stroking()
        erasing()
        clearing()

        print(failures == 0 ? "Screen draw tests passed" : "\(failures) screen draw tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static func stroke(_ tool: ScreenshotTool, on board: inout AnnotationBoard, from start: CGPoint, to end: CGPoint) {
        board.beginStroke(at: start, tool: tool, style: AnnotationStyle())
        board.drag(to: p((start.x + end.x) / 2, (start.y + end.y) / 2), constrained: false, metrics: metrics)
        board.drag(to: end, constrained: false, metrics: metrics)
        board.release()
    }

    static func erase(on board: inout AnnotationBoard, from start: CGPoint, to end: CGPoint) {
        board.beginErasing(at: start, metrics: metrics)
        board.drag(to: end, constrained: false, metrics: metrics)
        board.release()
    }

    static func keys() {
        let letters = DrawTool.allCases.map(\.key)
        let digits = AnnotationStyle.Ink.allCases.map(DrawKey.digit)
        expect(Set(letters + digits).count, letters.count + digits.count, "every tool and ink has its own key")
        expect(DrawKey("e"), .tool(.eraser), "E picks the eraser, as in Excalidraw")
        expect(DrawKey("1"), .ink(.red), "1 picks the first ink")
        expect(DrawKey("6"), .ink(.white), "6 picks the last ink")
        expect(DrawKey("z"), nil, "a letter with no tool picks nothing")
        for tool in DrawTool.allCases where tool != .eraser {
            expect(tool.markup?.key, tool.key, "\(tool.title) uses the screenshot tool's key")
        }
        expect(DrawTool.eraser.markup, nil, "the eraser draws nothing")
    }

    static func stroking() {
        var board = AnnotationBoard()
        stroke(.rectangle, on: &board, from: p(10, 10), to: p(60, 60))
        stroke(.pen, on: &board, from: p(10, 30), to: p(90, 30))
        expect(board.annotations.count, 2, "a stroke over a mark draws a new mark")
        expect(board.annotations[0].shape, .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)), "the mark under it stays put")
        board.beginStroke(at: p(200, 200), tool: .pen, style: AnnotationStyle())
        board.release()
        expect(board.annotations.count, 2, "a click without a drag leaves no mark")
    }

    static func erasing() {
        var board = AnnotationBoard()
        stroke(.pen, on: &board, from: p(0, 0), to: p(100, 0))
        stroke(.pen, on: &board, from: p(0, 50), to: p(100, 50))
        stroke(.pen, on: &board, from: p(0, 200), to: p(100, 200))
        erase(on: &board, from: p(50, -20), to: p(50, 70))
        expect(board.annotations.count, 1, "one drag erases every stroke it crosses")
        expect(board.annotations.first?.shape, .pen([p(0, 200), p(50, 200), p(100, 200)]), "a stroke it misses stays")
        board.undo()
        expect(board.annotations.count, 3, "one undo brings back the whole erase")
        erase(on: &board, from: p(300, 300), to: p(400, 400))
        board.undo()
        expect(board.annotations.count, 2, "an erase that removes nothing adds no undo step")
    }

    static func clearing() {
        var board = AnnotationBoard()
        board.clear()
        expect(board.canUndo, false, "clearing an empty board adds no undo step")
        stroke(.ellipse, on: &board, from: p(10, 10), to: p(60, 60))
        stroke(.highlighter, on: &board, from: p(0, 100), to: p(100, 100))
        board.clear()
        expect(board.annotations.isEmpty, true, "clear removes every mark")
        board.undo()
        expect(board.annotations.count, 2, "one undo brings back every cleared mark")
    }
}
