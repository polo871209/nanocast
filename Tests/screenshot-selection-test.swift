import CoreGraphics
import Foundation

@main
@MainActor
struct ScreenshotSelectionTests {
    static var failures = 0

    static let screen = PixelRect(x: 0, y: 0, width: 1000, height: 600)

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual != expected else { return }
        failures += 1
        print("FAIL: \(message)\n  expected \(expected)\n  actual   \(actual)")
    }

    static func main() {
        pixelRect()
        handles()
        drawing()
        moving()
        resizing()
        keyboard()
        windowSnap()
        chrome()
        fileName()
        color()

        print(failures == 0 ? "Screenshot selection tests passed" : "\(failures) screenshot selection tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func point(_ x: Int, _ y: Int) -> PixelPoint { PixelPoint(x: x, y: y) }

    static func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> PixelRect {
        PixelRect(x: x, y: y, width: width, height: height)
    }

    static func pixelRect() {
        expect(PixelRect(spanning: point(30, 40), point(10, 5)), rect(10, 5, 20, 35), "spanning normalises any corner order")
        expect(PixelRect(enclosing: CGRect(x: 1.5, y: 2.2, width: 3, height: 1)), rect(1, 2, 4, 2), "a fractional edge widens")
        expect(rect(0, 0, 10, 10).contains(point(10, 5)), false, "the max edge is outside")
        expect(rect(0, 0, 10, 10).intersection(rect(10, 0, 5, 5)), nil, "touching rects do not intersect")
        expect(point(-5, 700).clamped(to: screen), point(0, 600), "a point clamps to the grid lines")
    }

    static func handles() {
        let area = rect(100, 100, 200, 100)
        expect(SelectionHandle.at(point(102, 98), of: area, reach: 6), .topLeft, "a corner wins near both edges")
        expect(SelectionHandle.at(point(200, 104), of: area, reach: 6), .top, "the whole top edge is a handle")
        expect(SelectionHandle.at(point(305, 150), of: area, reach: 6), .right, "reach extends outside the area")
        expect(SelectionHandle.at(point(200, 150), of: area, reach: 6), nil, "the middle is no handle")
        expect(SelectionHandle.at(point(320, 150), of: area, reach: 6), nil, "past the reach is no handle")
        expect(SelectionHandle.at(point(100, 260), of: area, reach: 6), nil, "an edge ends with its reach")
    }

    static func drawing() {
        var edit = SelectionEdit(pressAt: point(100, 100), area: nil, bounds: screen, reach: 6, slop: 4)
        expect(edit.kind, .draw, "a press with no area draws")
        edit.drag(to: point(103, 102), square: false, panning: false)
        expect(edit.hasMoved, false, "a drag inside the slop is still a click")
        edit.drag(to: point(150, 130), square: false, panning: false)
        expect(edit.area, rect(100, 100, 50, 30), "a drag spans the press and the pointer")
        edit.drag(to: point(50, 20), square: false, panning: false)
        expect(edit.area, rect(50, 20, 50, 80), "a drag up and left keeps the press as a corner")
        edit.drag(to: point(1200, 900), square: false, panning: false)
        expect(edit.area, rect(100, 100, 900, 500), "the pointer clamps to the display")
        edit.drag(to: point(160, 120), square: true, panning: false)
        expect(edit.area, rect(100, 100, 60, 60), "Shift makes a square from the longer side")
        edit.drag(to: point(900, 590), square: true, panning: false)
        expect(edit.area, rect(100, 100, 500, 500), "a square stops at the nearest display edge")

        var panned = SelectionEdit(pressAt: point(100, 100), area: nil, bounds: screen, reach: 6, slop: 0)
        panned.drag(to: point(150, 150), square: false, panning: false)
        panned.drag(to: point(170, 160), square: false, panning: true)
        expect(panned.area, rect(120, 110, 50, 50), "Space moves the area being drawn")
        panned.drag(to: point(200, 200), square: false, panning: false)
        expect(panned.area, rect(120, 110, 80, 90), "releasing Space draws from the moved corner")
    }

    static func moving() {
        let area = rect(100, 100, 200, 100)
        var edit = SelectionEdit(pressAt: point(200, 150), area: area, bounds: screen, reach: 6, slop: 2)
        expect(edit.kind, .move, "a press inside the area moves it")
        edit.drag(to: point(250, 170), square: false, panning: false)
        expect(edit.area, rect(150, 120, 200, 100), "the area follows the pointer")
        edit.drag(to: point(2000, -500), square: false, panning: false)
        expect(edit.area, rect(800, 0, 200, 100), "a move stops at the display edge")
        edit.drag(to: point(210, 150), square: false, panning: false)
        expect(edit.area, rect(110, 100, 200, 100), "coming back needs no catching up")

        let outside = SelectionEdit(pressAt: point(600, 400), area: area, bounds: screen, reach: 6, slop: 2)
        expect(outside.kind, .draw, "a press outside the area draws a new one")
    }

    static func resizing() {
        let area = rect(100, 100, 200, 100)
        var corner = SelectionEdit(pressAt: point(300, 200), area: area, bounds: screen, reach: 6, slop: 0)
        expect(corner.kind, .resize(.bottomRight), "a press on a corner resizes")
        corner.drag(to: point(400, 260), square: false, panning: false)
        expect(corner.area, rect(100, 100, 300, 160), "the opposite corner stays put")
        corner.drag(to: point(50, 50), square: false, panning: false)
        expect(corner.area, rect(50, 50, 50, 50), "dragging past the fixed corner flips the area")

        var edge = SelectionEdit(pressAt: point(100, 150), area: area, bounds: screen, reach: 6, slop: 0)
        expect(edge.kind, .resize(.left), "a press on an edge resizes one axis")
        edge.drag(to: point(40, 400), square: false, panning: false)
        expect(edge.area, rect(40, 100, 260, 100), "an edge never moves the other axis")
        edge.drag(to: point(-30, 400), square: false, panning: false)
        expect(edge.area, rect(0, 100, 300, 100), "an edge clamps to the display")
    }

    static func keyboard() {
        let area = rect(100, 100, 200, 100)
        expect(SelectionEdit.moved(area, dx: 1, dy: 0, within: screen), rect(101, 100, 200, 100), "an arrow nudges 1 px")
        expect(SelectionEdit.moved(area, dx: 0, dy: -500, within: screen), rect(100, 0, 200, 100), "a nudge stops at the edge")
        expect(SelectionEdit.grown(area, dx: 10, dy: 0, within: screen), rect(100, 100, 210, 100), "⌘ grows from the right")
        expect(SelectionEdit.grown(area, dx: 0, dy: -500, within: screen), rect(100, 100, 200, 1), "a shrink keeps 1 px")
        expect(SelectionEdit.grown(area, dx: 5000, dy: 0, within: screen), rect(100, 100, 900, 100), "a grow stops at the edge")
    }

    static func windowSnap() {
        let display = CGRect(x: 1000, y: 0, width: 500, height: 300)
        let front = ScreenWindow(id: 1, frame: CGRect(x: 1100, y: 50, width: 100, height: 100))
        let back = ScreenWindow(id: 2, frame: CGRect(x: 1050, y: 20, width: 300, height: 200))
        let spanning = ScreenWindow(id: 3, frame: CGRect(x: 900, y: 100, width: 200, height: 100))
        func target(_ x: CGFloat, _ y: CGFloat, _ windows: [ScreenWindow]) -> WindowSnapPolicy.Target {
            WindowSnapPolicy.target(at: CGPoint(x: x, y: y), windows: windows, display: display, scale: 2)
        }
        expect(target(1150, 100, [front, back]).area, rect(200, 100, 200, 200), "the frontmost window wins, in device pixels")
        expect(target(1150, 100, [front, back]).window?.id, 1, "the target names the window it took")
        expect(
            target(1300, 30, [front, back]).area, rect(100, 40, 600, 400), "a window behind wins where the front one is absent")
        let split = target(1050, 150, [spanning])
        expect(split.area, rect(0, 200, 200, 200), "a window on two displays clips to this one")
        expect(split.window?.frame, rect(-200, 200, 400, 200), "the window's own frame keeps the part on the other display")
        expect(target(1400, 280, [front]).area, rect(0, 0, 1000, 600), "no window under the point takes the whole display")
        expect(target(1400, 280, [front]).window == nil, true, "the whole display names no window")
        windowShot()
    }

    static func windowShot() {
        let bounds = rect(0, 0, 100, 100)
        let image = makeImage(width: 40, height: 20)
        let shot = WindowShot(windowID: 7, display: 1, frame: rect(-10, 10, 40, 20), image: image)
        let exact = shot.exactImage(for: rect(0, 10, 30, 20), within: bounds)
        expect(exact.map { [$0.width, $0.height] }, [30, 20], "an area that is the window's visible part crops the window image")
        expect(shot.exactImage(for: rect(0, 10, 31, 20), within: bounds) == nil, true, "a resized area is no longer exact")
        let pending = WindowShot(windowID: 7, display: 1, frame: rect(-10, 10, 40, 20), image: nil)
        expect(pending.exactImage(for: rect(0, 10, 30, 20), within: bounds) == nil, true, "a pending window has no image yet")
    }

    static func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func chrome() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let size = CGSize(width: 120, height: 36)
        expect(
            ChromePlacement.toolbar(size: size, area: CGRect(x: 100, y: 100, width: 300, height: 200), in: bounds, gap: 8),
            CGRect(x: 280, y: 308, width: 120, height: 36), "the toolbar sits below, flush right")
        expect(
            ChromePlacement.toolbar(size: size, area: CGRect(x: 100, y: 300, width: 300, height: 280), in: bounds, gap: 8),
            CGRect(x: 280, y: 256, width: 120, height: 36), "no room below puts it above")
        expect(
            ChromePlacement.toolbar(size: size, area: bounds, in: bounds, gap: 8),
            CGRect(x: 872, y: 556, width: 120, height: 36), "a full-display area keeps it inside")
        expect(
            ChromePlacement.toolbar(size: size, area: CGRect(x: 0, y: 100, width: 50, height: 50), in: bounds, gap: 8),
            CGRect(x: 8, y: 158, width: 120, height: 36), "a narrow area at the left edge keeps it on screen")
        let pill = CGSize(width: 80, height: 20)
        expect(
            ChromePlacement.sizePill(size: pill, area: CGRect(x: 100, y: 100, width: 300, height: 200), in: bounds, gap: 4),
            CGRect(x: 100, y: 76, width: 80, height: 20), "the size pill sits above the top-left corner")
        expect(
            ChromePlacement.sizePill(size: pill, area: CGRect(x: 100, y: 10, width: 300, height: 200), in: bounds, gap: 4),
            CGRect(x: 100, y: 14, width: 80, height: 20), "no room above puts it inside")
        let loupe = CGSize(width: 120, height: 150)
        expect(
            ChromePlacement.loupe(size: loupe, cursor: CGPoint(x: 100, y: 100), in: bounds, offset: 20),
            CGRect(x: 120, y: 120, width: 120, height: 150), "the loupe trails the cursor")
        expect(
            ChromePlacement.loupe(size: loupe, cursor: CGPoint(x: 950, y: 550), in: bounds, offset: 20),
            CGRect(x: 810, y: 380, width: 120, height: 150), "the loupe flips at the corner")
        let options = CGSize(width: 200, height: 30)
        expect(
            ChromePlacement.optionsBar(
                size: options, toolbar: CGRect(x: 300, y: 308, width: 120, height: 36), in: bounds, gap: 4),
            CGRect(x: 300, y: 348, width: 200, height: 30), "the options bar hangs under the toolbar, left-aligned")
        expect(
            ChromePlacement.optionsBar(
                size: options, toolbar: CGRect(x: 300, y: 556, width: 120, height: 36), in: bounds, gap: 4),
            CGRect(x: 300, y: 522, width: 200, height: 30), "no room below puts it above the toolbar")
        expect(
            ChromePlacement.optionsBar(
                size: options, toolbar: CGRect(x: 872, y: 308, width: 120, height: 36), in: bounds, gap: 4),
            CGRect(x: 796, y: 348, width: 200, height: 30), "it stays on the display at the right edge")
    }

    static func fileName() {
        let date = Date(timeIntervalSince1970: 1_778_508_202)
        let utc = TimeZone(identifier: "UTC")!
        expect(
            ScreenshotFileName.name(at: date, in: utc) { _ in false }, "Screenshot 2026-05-11 at 14.03.22.png",
            "macOS's own spelling")
        var taken: Set<String> = ["Screenshot 2026-05-11 at 14.03.22.png", "Screenshot 2026-05-11 at 14.03.22 (2).png"]
        expect(
            ScreenshotFileName.name(at: date, in: utc) { taken.contains($0) }, "Screenshot 2026-05-11 at 14.03.22 (3).png",
            "a taken name is numbered")
        taken.removeAll()
        expect(
            ScreenshotFileName.name(at: date, in: TimeZone(identifier: "Asia/Shanghai")!) { taken.contains($0) },
            "Screenshot 2026-05-11 at 22.03.22.png", "the time zone is the caller's")
    }

    static func color() {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 16, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return expect(false, true, "a bitmap context") }
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        context.setFillColor(CGColor(srgbRed: 1, green: 0x80 / 255, blue: 0, alpha: 1))
        context.fill(CGRect(x: 3, y: 2, width: 1, height: 1))
        guard let image = context.makeImage() else { return expect(false, true, "a fixture image") }
        expect(PixelColor(image: image, at: point(3, 0))?.hex, "#FF8000", "the top-right pixel, top-left origin")
        expect(PixelColor(image: image, at: point(0, 2))?.hex, "#0000FF", "the bottom-left pixel")
        expect(PixelColor(image: image, at: point(4, 0)), nil, "a point past the image reads nothing")
    }
}
