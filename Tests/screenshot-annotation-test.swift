import CoreGraphics
import Foundation

@main
@MainActor
struct ScreenshotAnnotationTests {
    static var failures = 0

    static let metrics = AnnotationMetrics(
        scale: 1,
        points: AnnotationMetrics.Points(
            strokes: [1, 2, 4, 8], highlighters: [6, 10, 16, 24], textSizes: [10, 20, 30],
            brushes: [10, 20, 40], stepInset: 5, mosaicBlock: 10, blurBlock: 4, hitSlop: 4, dragSlop: 3,
            selectionOutset: 4),
        measureText: { text, size in CGSize(width: CGFloat(text.count) * size / 2, height: size) })

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual != expected else { return }
        failures += 1
        print("FAIL: \(message)\n  expected \(expected)\n  actual   \(actual)")
    }

    static func main() {
        tools()
        constraints()
        arrow()
        hitTesting()
        drawing()
        moving()
        editing()
        text()
        textMoving()
        steps()
        highlighter()
        layering()

        print(failures == 0 ? "Screenshot annotation tests passed" : "\(failures) screenshot annotation tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static func draw(
        _ tool: ScreenshotTool, on board: inout AnnotationBoard, from start: CGPoint, to end: CGPoint,
        style: AnnotationStyle = AnnotationStyle(), constrained: Bool = false
    ) {
        _ = board.press(at: start, tool: tool, style: style, metrics: metrics)
        board.drag(to: p((start.x + end.x) / 2, (start.y + end.y) / 2), constrained: constrained, metrics: metrics)
        board.drag(to: end, constrained: constrained, metrics: metrics)
        board.release()
    }

    static func tools() {
        let keys = ScreenshotTool.allCases.map(\.key)
        expect(Set(keys).count, keys.count, "every tool has its own key")
        expect(keys.contains("c"), false, "C stays free to copy the color under the loupe")
        expect(ScreenshotTool(key: "a"), .arrow, "A picks the arrow, as in Shottr")
        expect(ScreenshotTool(key: "z"), nil, "a letter with no tool picks nothing")
        expect(ScreenshotTool.allCases.filter(\.startsGroup), [.mosaic], "mosaic opens the second toolbar group")
    }

    static func constraints() {
        expect(AnnotationGeometry.square(from: p(10, 10), to: p(40, 20)), p(40, 40), "Shift squares on the longer side")
        expect(AnnotationGeometry.square(from: p(10, 10), to: p(0, 30)), p(-10, 30), "the square grows toward the drag")
        expect(AnnotationGeometry.snapped(from: p(0, 0), to: p(100, 8)), p(100, 0), "a shallow line snaps flat")
        expect(AnnotationGeometry.snapped(from: p(0, 0), to: p(50, 54)), p(52, 52), "a steep diagonal snaps to 45 degrees")
        expect(AnnotationGeometry.snapped(from: p(0, 0), to: p(-3, -90)), p(0, -90), "an upward line snaps vertical")
    }

    static func arrow() {
        let outline = AnnotationGeometry.arrowOutline(Annotation.Segment(start: p(0, 0), end: p(100, 0)), width: 4)
        expect(outline.count, 7, "an arrow is a closed seven-point outline")
        expect(outline[3], p(100, 0), "the tip is the drag's end")
        expect(outline[2], p(82, 9), "the head is 4.5 widths long")
        let short = AnnotationGeometry.arrowOutline(Annotation.Segment(start: p(0, 0), end: p(10, 0)), width: 4)
        expect(short[2].x, 0, "a short arrow's head shrinks to its length")
        expect(
            AnnotationGeometry.arrowOutline(Annotation.Segment(start: p(5, 5), end: p(5, 5)), width: 4), [], "no length, no arrow"
        )
    }

    static func hitTesting() {
        let style = AnnotationStyle()
        let box = Annotation(id: 1, shape: .rectangle(CGRect(x: 100, y: 100, width: 100, height: 50)), style: style)
        expect(AnnotationGeometry.hits(box, at: p(101, 120), metrics: metrics), true, "a box is reached on its edge")
        expect(AnnotationGeometry.hits(box, at: p(150, 125), metrics: metrics), false, "a box's middle is open to draw in")
        let oval = Annotation(id: 2, shape: .ellipse(CGRect(x: 0, y: 0, width: 100, height: 50)), style: style)
        expect(AnnotationGeometry.hits(oval, at: p(50, 1), metrics: metrics), true, "an ellipse is reached on its curve")
        expect(AnnotationGeometry.hits(oval, at: p(50, 25), metrics: metrics), false, "an ellipse's middle is open")
        let line = Annotation(id: 3, shape: .line(Annotation.Segment(start: p(0, 0), end: p(100, 0))), style: style)
        expect(AnnotationGeometry.hits(line, at: p(50, 6), metrics: metrics), true, "a line is reached beside it")
        expect(AnnotationGeometry.hits(line, at: p(120, 0), metrics: metrics), false, "a line ends at its end")
        let brush = Annotation(id: 4, shape: .mosaicStroke([p(0, 0), p(100, 0)]), style: style)
        expect(AnnotationGeometry.hits(brush, at: p(50, 0), metrics: metrics), false, "a mosaic stroke cannot be picked")
        let words = Annotation(id: 5, shape: .text("Hello", origin: p(10, 10)), style: style)
        expect(AnnotationGeometry.hits(words, at: p(40, 20), metrics: metrics), true, "text is reached anywhere in its box")
        expect(
            AnnotationGeometry.frame(of: words, metrics: metrics), CGRect(x: 10, y: 10, width: 50, height: 20),
            "text's frame is its measured box")
    }

    static func drawing() {
        var board = AnnotationBoard()
        draw(.rectangle, on: &board, from: p(10, 10), to: p(60, 40))
        expect(board.annotations.map(\.shape), [.rectangle(CGRect(x: 10, y: 10, width: 50, height: 30))], "a drag draws a box")
        expect(board.canUndo, true, "a drawn mark can be undone")
        draw(.ellipse, on: &board, from: p(100, 100), to: p(101, 101))
        expect(board.annotations.count, 1, "a drag inside the slop draws nothing")
        _ = board.press(at: p(100, 100), tool: .rectangle, style: AnnotationStyle(), metrics: metrics)
        board.drag(to: p(140, 130), constrained: false, metrics: metrics)
        board.drag(to: p(100, 100), constrained: false, metrics: metrics)
        board.release()
        expect(board.annotations.count, 1, "a drag that comes back to its start draws nothing")
        expect(board.draft == nil, true, "and leaves no draft behind")
        draw(.ellipse, on: &board, from: p(100, 100), to: p(140, 120), constrained: true)
        expect(board.annotations.last?.shape, .ellipse(CGRect(x: 100, y: 100, width: 40, height: 40)), "Shift draws a circle")
        draw(.pen, on: &board, from: p(0, 200), to: p(30, 230))
        expect(board.annotations.last?.shape, .pen([p(0, 200), p(15, 215), p(30, 230)]), "a pen keeps every sample")
        draw(.mosaic, on: &board, from: p(0, 300), to: p(50, 300))
        expect(board.annotations.last?.shape, .mosaicStroke([p(0, 300), p(25, 300), p(50, 300)]), "mosaic starts as a brush")
        board.undo()
        board.undo()
        expect(board.annotations.count, 2, "undo steps back one mark at a time")
        board.redo()
        expect(board.annotations.count, 3, "redo brings a mark back")
        draw(.line, on: &board, from: p(0, 400), to: p(100, 400))
        expect(board.canRedo, false, "a new mark drops what could be redone")
    }

    static func moving() {
        var board = AnnotationBoard()
        draw(.rectangle, on: &board, from: p(100, 100), to: p(200, 150))
        _ = board.press(at: p(101, 120), tool: .arrow, style: AnnotationStyle(), metrics: metrics)
        expect(board.selectedID, board.annotations.first?.id, "a press on a mark selects it, whatever the tool")
        board.drag(to: p(111, 125), constrained: false, metrics: metrics)
        expect(board.isMoving, true, "dragging a selected mark moves it")
        board.release()
        expect(
            board.annotations.first?.shape, .rectangle(CGRect(x: 110, y: 105, width: 100, height: 50)),
            "the mark moves with the drag")
        expect(board.annotations.count, 1, "moving draws nothing new")
        board.undo()
        expect(
            board.annotations.first?.shape, .rectangle(CGRect(x: 100, y: 100, width: 100, height: 50)),
            "undo puts a moved mark back")
        _ = board.press(at: p(101, 120), tool: .arrow, style: AnnotationStyle(), metrics: metrics)
        board.release()
        board.undo()
        expect(board.annotations.count, 0, "a click that never moved records no step")
    }

    static func editing() {
        var board = AnnotationBoard()
        draw(.rectangle, on: &board, from: p(100, 100), to: p(200, 150))
        _ = board.press(at: p(101, 120), tool: .rectangle, style: AnnotationStyle(), metrics: metrics)
        board.release()
        var blue = AnnotationStyle()
        blue.ink = .blue
        board.restyleSelected(blue)
        expect(board.annotations.first?.style.ink, .blue, "a style change restyles the selected mark")
        board.deleteSelected()
        expect(board.annotations.isEmpty, true, "Delete removes the selected mark")
        board.undo()
        expect(board.annotations.first?.style.ink, .blue, "undo brings a deleted mark back")
        board.undo()
        expect(board.annotations.first?.style.ink, .red, "undo takes back a restyle")
    }

    static func text() {
        var board = AnnotationBoard()
        expect(
            board.press(at: p(10, 10), tool: .text, style: AnnotationStyle(), metrics: metrics), true,
            "the text tool opens an edit")
        expect(board.isEmpty, false, "a text being typed counts as drawn")
        board.updateEditing("Hi")
        expect(board.visible.map(\.shape), [.text("Hi", origin: p(10, 10))], "typed text paints while it is typed")
        board.endEditing()
        expect(board.annotations.map(\.shape), [.text("Hi", origin: p(10, 10))], "ending the edit keeps the text")
        _ = board.press(at: p(200, 200), tool: .text, style: AnnotationStyle(), metrics: metrics)
        board.updateEditing("   ")
        board.endEditing()
        expect(board.annotations.count, 1, "blank text is dropped")
        board.undo()
        expect(board.annotations.isEmpty, true, "a dropped blank text leaves no undo step")
        board.redo()
        draw(.line, on: &board, from: p(0, 100), to: p(100, 100))
        expect(board.editText(at: p(12, 15), metrics: metrics), true, "a double-click opens typed text again")
        board.updateEditing("Hello")
        board.endEditing()
        expect(board.annotations.first?.shape, .text("Hello", origin: p(10, 10)), "re-edited text keeps its place in the order")
        board.undo()
        expect(board.annotations.first?.shape, .text("Hi", origin: p(10, 10)), "undo restores the text before the edit")
        _ = board.editText(at: p(12, 15), metrics: metrics)
        board.updateEditing("")
        board.endEditing()
        expect(board.annotations.map(\.isTyped), [false], "clearing typed text deletes it")
        board.undo()
        expect(board.annotations.first?.typedText, "Hi", "undo brings a cleared text back")
    }

    static func textMoving() {
        var board = AnnotationBoard()
        _ = board.press(at: p(10, 10), tool: .text, style: AnnotationStyle(), metrics: metrics)
        board.updateEditing("Hi")
        expect(board.gripsEditing(at: p(5, 20), metrics: metrics), true, "the box around a text being typed is a grip")
        expect(board.gripsEditing(at: p(20, 20), metrics: metrics), false, "the text itself is left to the text view")
        expect(board.gripsEditing(at: p(60, 20), metrics: metrics), false, "a click past the box is no grip")
        expect(board.grabEditing(at: p(5, 20), metrics: metrics), true, "a press on the box grabs the text")
        board.drag(to: p(45, 60), constrained: false, metrics: metrics)
        expect(board.isMoving, true, "dragging the box moves the text")
        board.release()
        expect(board.editing?.shape, .text("Hi", origin: p(50, 50)), "the text being typed follows the box")
        board.endEditing()
        expect(board.annotations.map(\.shape), [.text("Hi", origin: p(50, 50))], "the text lands where it was dragged")

        _ = board.press(at: p(55, 55), tool: .text, style: AnnotationStyle(), metrics: metrics)
        expect(board.editing == nil, true, "a press on typed text waits to see a click or a drag")
        board.drag(to: p(85, 75), constrained: false, metrics: metrics)
        board.release()
        expect(board.editing == nil, true, "a drag with the text tool does not open the edit")
        expect(board.annotations.first?.shape, .text("Hi", origin: p(80, 70)), "the text tool drags typed text")
        board.undo()
        expect(board.annotations.first?.shape, .text("Hi", origin: p(50, 50)), "undo puts dragged text back")

        _ = board.press(at: p(55, 55), tool: .text, style: AnnotationStyle(), metrics: metrics)
        board.release()
        expect(board.editing?.typedText, "Hi", "a click with the text tool opens typed text")
        board.endEditing()
        _ = board.press(at: p(55, 55), tool: .arrow, style: AnnotationStyle(), metrics: metrics)
        board.release()
        expect(board.editing == nil, true, "a click with another tool only selects typed text")
    }

    static func click(_ tool: ScreenshotTool, on board: inout AnnotationBoard, at point: CGPoint) {
        _ = board.press(at: point, tool: tool, style: AnnotationStyle(), metrics: metrics)
        board.release()
    }

    static func steps() {
        var board = AnnotationBoard()
        click(.step, on: &board, at: p(100, 100))
        expect(board.annotations.map(\.shape), [.step(center: p(100, 100))], "a click places a step")
        click(.step, on: &board, at: p(200, 100))
        click(.step, on: &board, at: p(300, 100))
        expect(board.annotations.count, 3, "each click places the next step")
        let circle = AnnotationGeometry.stepCircle(at: p(100, 100), style: AnnotationStyle(), metrics: metrics)
        expect(circle, CGRect(x: 85, y: 85, width: 30, height: 30), "a step's circle fits its number with an inset")
        click(.step, on: &board, at: p(210, 105))
        expect(board.annotations.count, 3, "a click on a step picks it up instead of placing another")
        board.deleteSelected()
        expect(board.annotations.map(\.shape), [.step(center: p(100, 100)), .step(center: p(300, 100))], "a step deletes")
        _ = board.press(at: p(400, 100), tool: .step, style: AnnotationStyle(), metrics: metrics)
        board.drag(to: p(420, 140), constrained: false, metrics: metrics)
        board.release()
        expect(board.annotations.last?.shape, .step(center: p(420, 140)), "a drag carries a new step to where it lands")
        board.undo()
        expect(board.annotations.count, 2, "one undo takes back one placed step")
    }

    static func highlighter() {
        var board = AnnotationBoard()
        draw(.highlighter, on: &board, from: p(0, 0), to: p(100, 8))
        expect(board.annotations.last?.shape, .highlighter([p(0, 0), p(100, 8)]), "a highlighter draws straight by default")
        draw(.highlighter, on: &board, from: p(0, 50), to: p(100, 58), constrained: true)
        expect(board.annotations.last?.shape, .highlighter([p(0, 50), p(100, 50)]), "Shift levels a straight highlighter")
        var freehand = AnnotationStyle()
        freehand.highlighterFreehand = true
        draw(.highlighter, on: &board, from: p(0, 100), to: p(40, 120), style: freehand)
        expect(
            board.annotations.last?.shape, .highlighter([p(0, 100), p(20, 110), p(40, 120)]), "freehand keeps every sample")
        let stroke = board.annotations[0]
        expect(
            AnnotationGeometry.hits(stroke, at: p(50, 11), metrics: metrics), true, "a highlighter is reached across its width")
        expect(
            AnnotationGeometry.frame(of: stroke, metrics: metrics), CGRect(x: -8, y: -8, width: 116, height: 24),
            "a highlighter's frame holds its whole width")
    }

    static func layering() {
        var board = AnnotationBoard()
        draw(.rectangle, on: &board, from: p(10, 10), to: p(60, 60))
        var box = AnnotationStyle()
        box.mosaicBrush = false
        draw(.mosaic, on: &board, from: p(90, 90), to: p(10, 10), style: box)
        draw(.mosaic, on: &board, from: p(20, 20), to: p(70, 70), style: box)
        expect(board.visible.map(\.isMosaic), [true, true, false], "mosaic paints under every mark")
        let hit = board.annotation(at: p(10, 30), metrics: metrics)
        expect(hit.map(\.id), board.annotations.first?.id, "a mark wins a press over a mosaic edge under it")
    }
}
