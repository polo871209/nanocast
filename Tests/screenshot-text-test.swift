import CoreText
import Foundation

@main
@MainActor
struct ScreenshotTextTests {
    static var failures = 0

    static func main() async throws {
        let words = (0..<120).map { "word\($0 * 37 % 1000)x" }
        let small = canvas(width: 1200, height: 600)
        draw("Quarterly report 7391", in: small, at: CGPoint(x: 40, y: 80))
        let smallText = try await ScreenshotTextExtractor.extract(from: small.makeImage()!)
        expect(smallText.contains("Quarterly report 7391"), "reads a small capture in one tile")

        let wide = canvas(width: 5120, height: 2880)
        for (index, word) in words.enumerated() {
            draw(word, in: wide, at: CGPoint(x: 60 + index % 6 * 840, y: 60 + index / 6 * 136))
        }
        draw("ACROSS THE SEAM 4826", in: wide, at: CGPoint(x: 1900, y: 2440))
        let wideText = try await ScreenshotTextExtractor.extract(from: wide.makeImage()!)
        let found = words.filter(wideText.contains).count
        expect(found >= words.count * 95 / 100, "reads a 5K capture through tiles, found \(found)/\(words.count)")
        let seam = wideText.components(separatedBy: "ACROSS THE SEAM 4826").count - 1
        expect(seam == 1, "a line in a tile overlap is read once, read \(seam) times")

        let long = canvas(width: 2400, height: 20_000)
        for row in 0..<550 {
            let sentence = String(repeating: "lorem ipsum dolor sit amet ", count: 4)
            draw(sentence, in: long, at: CGPoint(x: 40, y: 20 + row * 36), size: 24)
        }
        let longText = try await ScreenshotTextExtractor.extract(from: long.makeImage()!)
        expect(longText.utf8.count > ClipboardTextExtractor.maximumTextBytes - 200, "reads a long capture to the bound")
        expect(longText.utf8.count <= ClipboardTextExtractor.maximumTextBytes, "text is bounded")
        exit(failures == 0 ? 0 : 1)
    }

    static func canvas(width: Int, height: Int) -> CGContext {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        return context
    }

    static func draw(_ text: String, in context: CGContext, at origin: CGPoint, size: CGFloat = 40) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                "Helvetica" as CFString, size, nil)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y + size)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    static func expect(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }
}
