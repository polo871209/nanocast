import AppKit
import CoreGraphics

@main
@MainActor
struct ScreenshotRenderTests {
    static var failures = 0

    struct RGBA: Equatable, CustomStringConvertible {
        let r: UInt8, g: UInt8, b: UInt8, a: UInt8
        var description: String { "(\(r), \(g), \(b), \(a))" }
    }

    static let gray = RGBA(r: 128, g: 128, b: 128, a: 255)
    static let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    static let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    static let metrics = AnnotationMetrics(
        scale: 1,
        points: AnnotationMetrics.Points(
            strokes: [1, 2, 4, 8], highlighters: [6, 10, 16, 24], textSizes: [10, 20, 30],
            brushes: [10, 20, 40], stepInset: 5, mosaicBlock: 10, blurBlock: 4, hitSlop: 4, dragSlop: 3,
            selectionOutset: 4),
        measureText: { AnnotationText.size(of: $0, fontSize: $1) })

    static func painter(mosaic: MosaicSource? = nil) -> AnnotationPainter {
        let inks = Dictionary(
            uniqueKeysWithValues: AnnotationStyle.Ink.allCases.map { ($0, CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) })
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        return AnnotationPainter(
            metrics: metrics,
            palette: AnnotationPainter.Palette(
                inks: inks, highlighterAlpha: 0.5, lightText: white, darkText: black, rim: white),
            mosaic: mosaic)
    }

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual != expected else { return }
        failures += 1
        print("FAIL: \(message)\n  expected \(expected)\n  actual   \(actual)")
    }

    static func main() {
        upright()
        plainCrop()
        marks()
        windowShots()
        highlighter()
        steps()
        mosaic()
        typedText()

        print(failures == 0 ? "Screenshot render tests passed" : "\(failures) screenshot render tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func display(_ image: CGImage) -> CapturedDisplay {
        CapturedDisplay(
            id: 1, image: image, frame: CGRect(x: 0, y: 0, width: image.width, height: image.height),
            quartzFrame: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    static func render(
        _ area: PixelRect, on screen: CGImage, window: WindowShot? = nil, _ annotations: [Annotation] = [],
        mosaic: MosaicSource? = nil
    ) -> CGImage? {
        ScreenshotRenderer.image(
            of: area, on: display(screen), window: window, annotations: annotations, painter: painter(mosaic: mosaic))
    }

    static func image(width: Int, height: Int, fill: (Int, Int) -> RGBA = { _, _ in gray }) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let color = fill(x, y)
                let index = (y * width + x) * 4
                bytes[index] = color.r
                bytes[index + 1] = color.g
                bytes[index + 2] = color.b
                bytes[index + 3] = color.a
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: srgb,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func pixel(_ image: CGImage?, _ x: Int, _ y: Int) -> RGBA? {
        guard let image else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return RGBA(r: bytes[0], g: bytes[1], b: bytes[2], a: bytes[3])
    }

    static func upright() {
        let source = image(width: 4, height: 4) { _, y in y == 0 ? red : gray }
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: 4)
        context.scaleBy(x: 1, y: -1)
        context.drawUpright(source, in: CGRect(x: 0, y: 0, width: 4, height: 4))
        let drawn = context.makeImage()
        expect(pixel(drawn, 1, 0), red, "an upright draw keeps the top row on top in a top-left context")
        expect(pixel(drawn, 1, 3), gray, "and the bottom row at the bottom")
    }

    static func plainCrop() {
        let screen = image(width: 200, height: 100) { x, _ in x < 100 ? gray : blue }
        let crop = render(PixelRect(x: 90, y: 10, width: 20, height: 20), on: screen)
        expect(crop.map { [$0.width, $0.height] }, [20, 20], "an unmarked area is a plain crop")
        expect(pixel(crop, 5, 5), gray, "the crop starts at the area's left edge")
        expect(pixel(crop, 15, 5), blue, "and keeps the screen's pixels")
        let owned = crop.flatMap(ScreenshotRenderer.ownCopy)
        expect(owned.map { [$0.width, $0.height] }, [20, 20], "a pin's own copy keeps the crop's size")
        expect(pixel(owned, 15, 5), blue, "and its pixels")
    }

    static func marks() {
        let screen = image(width: 300, height: 200)
        let box = Annotation(
            id: 1, shape: .rectangle(CGRect(x: 60, y: 60, width: 80, height: 40)), style: AnnotationStyle())
        let arrow = Annotation(
            id: 2, shape: .arrow(Annotation.Segment(start: CGPoint(x: 60, y: 150), end: CGPoint(x: 160, y: 150))),
            style: AnnotationStyle())
        let shot = render(PixelRect(x: 50, y: 50, width: 150, height: 120), on: screen, [box, arrow])
        expect(pixel(shot, 10, 20), red, "a box's left edge paints at its place in the area")
        expect(pixel(shot, 50, 20), gray, "a box's middle keeps the screen")
        expect(pixel(shot, 105, 100), red, "an arrow's head paints at its end, top-left down")
        expect(pixel(shot, 105, 90), gray, "and not mirrored above it")
        let clipped = render(PixelRect(x: 100, y: 0, width: 50, height: 50), on: screen, [box])
        expect(clipped.map(\.height), 50, "a mark outside the area changes nothing about its size")
        expect(pixel(clipped, 25, 25), gray, "a mark outside the area is clipped off")
    }

    static func windowShots() {
        let screen = image(width: 200, height: 200)
        let corner = image(width: 60, height: 40) { x, y in x < 4 && y < 4 ? RGBA(r: 0, g: 0, b: 0, a: 0) : blue }
        let window = WindowShot(windowID: 9, display: 1, frame: PixelRect(x: 20, y: 30, width: 60, height: 40), image: corner)
        let exact = render(PixelRect(x: 20, y: 30, width: 60, height: 40), on: screen, window: window)
        expect(pixel(exact, 1, 1)?.a, 0, "a window's own shot keeps its transparent corner")
        expect(pixel(exact, 30, 20), blue, "and its own pixels")
        let wider = render(PixelRect(x: 10, y: 30, width: 80, height: 40), on: screen, window: window)
        expect(pixel(wider, 5, 20), gray, "past the window, the frozen screen shows")
        expect(pixel(wider, 40, 20), blue, "inside it, the window's own pixels cover the screen")
        let line = Annotation(
            id: 1, shape: .line(Annotation.Segment(start: CGPoint(x: 30, y: 50), end: CGPoint(x: 70, y: 50))),
            style: AnnotationStyle())
        let marked = render(PixelRect(x: 20, y: 30, width: 60, height: 40), on: screen, window: window, [line])
        expect(pixel(marked, 1, 1)?.a, 0, "a marked window shot keeps its transparent corner")
        expect(pixel(marked, 30, 20), red, "with the mark over the window")
        let pending = WindowShot(windowID: 9, display: 1, frame: window.frame, image: nil)
        expect(
            pixel(render(window.frame, on: screen, window: pending), 30, 20), gray, "a pending window falls back to the screen")
    }

    static func highlighter() {
        let screen = image(width: 100, height: 100)
        let mixed = RGBA(r: 192, g: 64, b: 64, a: 255)
        let straight = Annotation(
            id: 1, shape: .highlighter([CGPoint(x: 10, y: 20), CGPoint(x: 90, y: 20)]), style: AnnotationStyle())
        let shot = render(PixelRect(x: 0, y: 0, width: 100, height: 100), on: screen, [straight])
        expect(pixel(shot, 50, 20), mixed, "a highlighter lets half the screen through")
        expect(pixel(shot, 50, 26), mixed, "across its whole width")
        expect(pixel(shot, 50, 40), gray, "and leaves the rest alone")
        var freehand = AnnotationStyle()
        freehand.highlighterFreehand = true
        let loop = Annotation(
            id: 2,
            shape: .highlighter([
                CGPoint(x: 10, y: 60), CGPoint(x: 90, y: 60), CGPoint(x: 90, y: 62), CGPoint(x: 10, y: 62)
            ]), style: freehand)
        let crossed = render(PixelRect(x: 0, y: 0, width: 100, height: 100), on: screen, [loop])
        expect(pixel(crossed, 50, 61), mixed, "a stroke over itself does not darken")
    }

    static func steps() {
        let screen = image(width: 100, height: 100)
        let step = Annotation(id: 1, shape: .step(center: CGPoint(x: 50, y: 50)), style: AnnotationStyle())
        let shot = render(PixelRect(x: 0, y: 0, width: 100, height: 100), on: screen, [step])
        expect(pixel(shot, 38, 50), red, "a step is a circle filled with the ink")
        expect(pixel(shot, 50, 34).map { $0.g > 160 && $0.b > 160 }, true, "inside a light rim")
        expect(pixel(shot, 50, 30), gray, "and nothing past it")
        expect(pixel(shot, 50, 50) == red, false, "with its number in the middle")
    }

    static func mosaic() {
        let screen = image(width: 100, height: 100) { x, y in (x + y) % 2 == 0 ? red : blue }
        let source = MosaicSource(screen: screen, window: nil, block: 10, blurBlock: 4)
        let box = Annotation(id: 1, shape: .mosaicBox(CGRect(x: 0, y: 0, width: 50, height: 50)), style: AnnotationStyle())
        let shot = render(PixelRect(x: 0, y: 0, width: 100, height: 100), on: screen, [box], mosaic: source)
        expect(pixel(shot, 2, 2), pixel(shot, 7, 6), "a pixelated block is one color")
        expect(pixel(shot, 2, 2) == red || pixel(shot, 2, 2) == blue, false, "the block mixes the pixels under it")
        expect(pixel(shot, 70, 70), red, "past the box the screen is untouched")
        var blur = AnnotationStyle()
        blur.mosaicEffect = .blur
        let blurred = render(
            PixelRect(x: 0, y: 0, width: 100, height: 100), on: screen,
            [Annotation(id: 2, shape: .mosaicBox(CGRect(x: 0, y: 0, width: 50, height: 50)), style: blur)],
            mosaic: source)
        expect(pixel(blurred, 20, 20) == red || pixel(blurred, 20, 20) == blue, false, "a blur hides the pattern too")
        let windowed = MosaicSource(
            screen: screen,
            window: WindowShot(
                windowID: 1, display: 1, frame: PixelRect(x: 0, y: 0, width: 100, height: 100),
                image: image(width: 100, height: 100) { _, _ in blue }),
            block: 10, blurBlock: 4)
        let hidden = render(PixelRect(x: 0, y: 0, width: 100, height: 100), on: screen, [box], mosaic: windowed)
        expect(pixel(hidden, 5, 5), blue, "a mosaic over a clicked window hides the window's own pixels")
    }

    static func typedText() {
        let screen = image(width: 200, height: 100)
        let words = Annotation(id: 1, shape: .text("WWW", origin: CGPoint(x: 10, y: 10)), style: AnnotationStyle())
        let shot = render(PixelRect(x: 0, y: 0, width: 200, height: 100), on: screen, [words])
        let frame = AnnotationGeometry.frame(of: words, metrics: metrics)
        let inked = (Int(frame.minX)..<Int(frame.maxX)).contains { x in
            (Int(frame.minY)..<Int(frame.maxY)).contains { y in pixel(shot, x, y) == red }
        }
        expect(inked, true, "text paints inside its measured box")
        expect(pixel(shot, 10, Int(frame.maxY) + 4), gray, "and nothing under it")
        let hidden = painter()
        let context = CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: 100)
        context.scaleBy(x: 1, y: -1)
        hidden.paint([words], in: context, area: CGRect(x: 0, y: 0, width: 200, height: 100), hiddenText: 1)
        let blank = context.makeImage()
        let untouched = (Int(frame.minX)..<Int(frame.maxX)).allSatisfy { x in pixel(blank, x, Int(frame.midY))?.a == 0 }
        expect(untouched, true, "the text being typed is left to its text view")
    }
}
