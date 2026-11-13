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
        typing()
        erasing()
        clearing()
        selecting()

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
        expect(DrawKey("v"), .tool(.select), "V picks the select tool, as in Excalidraw")
        expect(DrawKey("1"), .ink(.red), "1 picks the first ink")
        expect(DrawKey("6"), .ink(.white), "6 picks the last ink")
        expect(DrawKey("z"), nil, "a letter with no tool picks nothing")
        for tool in DrawTool.allCases where tool != .select && tool != .eraser {
            expect(tool.markup?.key, tool.key, "\(tool.title) uses the screenshot tool's key")
        }
        expect(DrawTool.eraser.markup, nil, "the eraser draws nothing")
        expect(DrawTool.select.markup, nil, "the select tool draws nothing")
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
        stroke(.line, on: &board, from: p(0, 100), to: p(100, 100))
        expect(board.annotations.last?.shape, .line(.init(start: p(0, 100), end: p(100, 100))), "a line runs end to end")
        stroke(.arrow, on: &board, from: p(0, 150), to: p(100, 150))
        expect(board.annotations.last?.shape, .arrow(.init(start: p(0, 150), end: p(100, 150))), "an arrow points at the release")
    }

    static func typing() {
        var board = AnnotationBoard()
        stroke(.rectangle, on: &board, from: p(10, 10), to: p(200, 200))
        board.beginText(at: p(50, 50), style: AnnotationStyle())
        board.updateEditing("Hello")
        expect(board.visible.last?.typedText, "Hello", "the text shows while it is typed")
        board.endEditing()
        expect(board.annotations.last?.shape, .text("Hello", origin: p(50, 50)), "a text typed over a mark is its own mark")
        board.undo()
        expect(board.annotations.count, 1, "one undo takes the text back")
        board.beginText(at: p(300, 300), style: AnnotationStyle())
        board.endEditing()
        expect(board.annotations.count, 1, "an empty text leaves no mark")
        board.redo()
        expect(board.annotations.count, 2, "redo still brings the text back after an empty one")
        expect(board.editText(at: p(52, 55), metrics: metrics), true, "a click on a text types into it again")
        board.updateEditing("Hello there")
        board.endEditing()
        expect(board.annotations.last?.typedText, "Hello there", "the edited text replaces the old one")
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

    static func click(on board: inout AnnotationBoard, at point: CGPoint, adding: Bool = false) {
        board.beginSelecting(at: point, adding: adding, metrics: metrics)
        board.release()
    }

    static func select(on board: inout AnnotationBoard, from start: CGPoint, to end: CGPoint) {
        board.beginSelecting(at: start, adding: false, metrics: metrics)
        board.drag(to: end, constrained: false, metrics: metrics)
        board.release()
    }

    static func selecting() {
        var board = AnnotationBoard()
        let square = Annotation.Shape.rectangle(CGRect(x: 10, y: 10, width: 50, height: 50))
        stroke(.rectangle, on: &board, from: p(10, 10), to: p(60, 60))
        stroke(.pen, on: &board, from: p(100, 30), to: p(200, 30))
        board.beginText(at: p(300, 300), style: AnnotationStyle())
        board.updateEditing("Hi")
        board.endEditing()
        let ids = board.annotations.map(\.id)
        expect(board.selectedIDs, [], "drawing selects nothing")

        select(on: &board, from: p(10, 30), to: p(15, 40))
        expect(board.annotations[0].shape, .rectangle(CGRect(x: 15, y: 20, width: 50, height: 50)), "a drag on a shape moves it")
        expect(board.selectedIDs, [ids[0]], "the moved shape stays selected")
        board.undo()
        expect(board.annotations[0].shape, square, "one undo puts the shape back")
        select(on: &board, from: p(310, 310), to: p(330, 310))
        expect(board.annotations[2].shape, .text("Hi", origin: p(320, 300)), "a drag on a text moves it")

        board.beginSelecting(at: p(0, 0), adding: false, metrics: metrics)
        board.drag(to: p(250, 100), constrained: false, metrics: metrics)
        expect(board.marquee, CGRect(x: 0, y: 0, width: 250, height: 100), "a drag on an empty spot shows a box")
        board.release()
        expect(board.selectedIDs, [ids[0], ids[1]], "the box selects every mark inside it")
        expect(board.marquee, nil, "the box goes away on release")
        select(on: &board, from: p(150, 30), to: p(150, 80))
        expect(
            board.annotations[0].shape, .rectangle(CGRect(x: 10, y: 60, width: 50, height: 50)),
            "a drag moves every selected mark")
        expect(board.annotations[1].shape, .pen([p(100, 80), p(150, 80), p(200, 80)]), "the stroke moves with the shape")
        expect(board.annotations[2].shape, .text("Hi", origin: p(320, 300)), "an unselected mark stays put")
        board.undo()
        expect(board.annotations[0].shape, square, "one undo puts the whole group back")

        click(on: &board, at: p(10, 30))
        click(on: &board, at: p(330, 310), adding: true)
        expect(board.selectedIDs, [ids[0], ids[2]], "shift-click adds a mark")
        click(on: &board, at: p(10, 30), adding: true)
        expect(board.selectedIDs, [ids[2]], "shift-click on a selected mark drops it")
        board.selectAll()
        click(on: &board, at: p(150, 30))
        expect(board.selectedIDs, [ids[1]], "a click on one mark of a group selects only that mark")
        click(on: &board, at: p(500, 500))
        expect(board.selectedIDs, [], "a click on an empty spot selects nothing")

        var blue = AnnotationStyle()
        blue.ink = .blue
        board.selectAll()
        board.restyleSelected(blue)
        expect(board.annotations.map(\.style.ink), [.blue, .blue, .blue], "an ink recolours every selected mark")
        board.selectAll()
        board.deleteSelected()
        expect(board.annotations.isEmpty, true, "delete removes every selected mark")
        board.undo()
        expect(board.annotations.count, 3, "one undo brings back the deleted marks")
        board.undo()
        let ink = AnnotationStyle().ink
        expect(board.annotations.map(\.style.ink), [ink, ink, ink], "one undo takes the ink back")
    }
}
