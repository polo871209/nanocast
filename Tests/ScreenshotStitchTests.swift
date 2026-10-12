import CoreGraphics
import Foundation

@main
@MainActor
struct ScreenshotStitchTests {
    static var failures = 0

    static let width = 200
    static let band = 12
    static let viewport = 160
    static let header = 14
    static let footer = 10
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual != expected else { return }
        failures += 1
        print("FAIL: \(message)\n  expected \(expected)\n  actual   \(actual)")
    }

    static func main() {
        stillness()
        rebuild()
        noise()
        repeats()
        blankOverlap()
        hover()
        lost()
        cap()
        file()

        print(failures == 0 ? "Screenshot stitch tests passed" : "\(failures) screenshot stitch tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func randomRow(_ generator: inout some RandomNumberGenerator) -> [UInt32] {
        (0..<width).map { _ in UInt32.random(in: 0...UInt32.max, using: &generator) | 0xFF00_0000 }
    }

    static let blank = Array(repeating: UInt32(0xFFFF_FFFF), count: width)

    static let page: [[UInt32]] = {
        var generator = SystemRandomNumberGenerator()
        return (0..<900).map { y in
            (200..<240).contains(y) || (450..<470).contains(y) ? blank : randomRow(&generator)
        }
    }()

    static let headerRows = (0..<header).map { y in Array(repeating: UInt32(0xFF11_0000) + UInt32(y * 3), count: width) }
    static let footerRows = (0..<footer).map { y in (0..<width).map { UInt32(0xFF00_2200) + UInt32(y * 64 + $0) } }

    static func frame(of page: [[UInt32]], at offset: Int, noisy: Bool = false) -> [[UInt32]] {
        var generator = SystemRandomNumberGenerator()
        let middle = page[(offset + header)..<(offset + viewport - footer)]
        return (headerRows + middle + footerRows).enumerated().map { y, row in
            var row = row
            if noisy {
                for x in row.indices where Bool.random(using: &generator) { row[x] ^= 0x0001_0101 }
            }
            for x in (width - band)..<width { row[x] = (y + offset) % 50 < 10 ? 0xFF88_8888 : 0xFF22_2222 }
            return row
        }
    }

    static func scrollFrame(_ rows: [[UInt32]]) -> ScrollFrame {
        let pixels = rows.flatMap { $0 }
        let image = pixels.withUnsafeBytes { bytes in
            CGImage(
                width: width, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: space, bitmapInfo: ScrollFrame.bitmapInfo, provider: CGDataProvider(data: Data(bytes) as CFData)!,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        }
        return ScrollFrame(image: image, ignoringRight: band)!
    }

    static func rows(of frame: ScrollFrame) -> [[UInt32]] {
        frame.pixels.withUnsafeBytes { bytes in
            (0..<frame.height).map { y in
                (0..<width).map { bytes.load(fromByteOffset: y * frame.bytesPerRow + $0 * 4, as: UInt32.self) }
            }
        }
    }

    static func stitch(
        _ offsets: [Int], of page: [[UInt32]] = page, noisy: Bool = false, expected: ((Int) -> Int)? = nil,
        cap: Int = 10_000
    ) -> (rows: [[UInt32]], steps: [ScrollStitch.Step]) {
        var stitch = ScrollStitch(cap: cap)
        var image: [[UInt32]] = []
        var steps: [ScrollStitch.Step] = []
        var last = offsets.first ?? 0
        for offset in offsets {
            let shown = rows(of: scrollFrame(frame(of: page, at: offset, noisy: noisy)))
            let step = stitch.add(
                scrollFrame(shown).profile, expected: expected?(offset - last) ?? (offset - last))
            switch step {
            case .started(let added): image = Array(shown[added])
            case .extended(let keep, let added):
                image = Array(image.prefix(keep)) + shown[added]
                last = offset
            case .unchanged, .lost, .full: break
            }
            steps.append(step)
        }
        expect(image.count, stitch.height, "the stitch's height counts the rows written")
        return (image, steps)
    }

    static func expectedImage(of page: [[UInt32]] = page, through end: Int) -> [[UInt32]] {
        headerRows + page[header..<(end + viewport - footer)] + footerRows
    }

    static func firstDifference(_ actual: [[UInt32]], _ expected: [[UInt32]]) -> Int? {
        func close(_ a: UInt32, _ b: UInt32) -> Bool {
            (0..<3).allSatisfy { abs(Int((a >> ($0 * 8)) & 0xFF) - Int((b >> ($0 * 8)) & 0xFF)) <= 1 }
        }
        let differing = (0..<min(actual.count, expected.count)).first { y in
            !zip(actual[y].prefix(width - band), expected[y].prefix(width - band)).allSatisfy(close)
        }
        return differing ?? (actual.count == expected.count ? nil : min(actual.count, expected.count))
    }

    static func stillness() {
        let shown = frame(of: page, at: 100)
        var caret = shown
        caret[50] = blank
        expect(scrollFrame(shown).profile.isStill(comparedTo: scrollFrame(caret).profile), true, "a blinking caret is still")
        let moved = scrollFrame(frame(of: page, at: 101)).profile
        expect(scrollFrame(shown).profile.isStill(comparedTo: moved), false, "one row of scroll is not")
    }

    static func rebuild() {
        let end = page.count - viewport
        let offsets = [0, 0, 30, 75, 110, 180, 230, 300, 390, 470, 540, 620, 700, end, end]
        let (image, steps) = stitch(offsets)
        expect(
            firstDifference(image, expectedImage(through: end)), nil,
            "the stitch rebuilds the page with one header and one footer")
        expect(steps[1], .unchanged, "a frame that did not move adds nothing")
        expect(steps.last, .unchanged, "the end of the page adds nothing")
    }

    static func noise() {
        let end = page.count - viewport
        let (image, steps) = stitch([0, 60, 130, 200, 290, 380, 470, 560, 650, end], noisy: true)
        expect(steps.filter { $0 == .lost }.count, 0, "a level of noise on every pixel never loses the page")
        expect(firstDifference(image, expectedImage(through: end)), nil, "and the page comes back whole")
    }

    static func repeats() {
        var generator = SystemRandomNumberGenerator()
        let item = (0..<20).map { _ in randomRow(&generator) }
        let list = (0..<600).map { item[$0 % 20] }
        let (image, _) = stitch([0, 50, 100, 150, 200, 250, 300], of: list)
        expect(
            firstDifference(image, expectedImage(of: list, through: 300)), nil,
            "a repeating list stitches at the scroll's own offset")
        let (short, _) = stitch([0, 50, 100], of: list, expected: { $0 + 20 })
        expect(
            short.count, expectedImage(of: list, through: 100).count + 40, "a scroll that asked for one period more lands there")
    }

    static func blankOverlap() {
        var generator = SystemRandomNumberGenerator()
        let sparse = (0..<700).map { y in (300..<500).contains(y) ? blank : randomRow(&generator) }
        let (image, _) = stitch([0, 80, 160, 260, 340, 400, 480, 540], of: sparse)
        expect(firstDifference(image, expectedImage(of: sparse, through: 540)), nil, "a blank stretch follows the scroll")
    }

    static func hover() {
        var stitch = ScrollStitch(cap: 10_000)
        _ = stitch.add(scrollFrame(frame(of: page, at: 100)).profile, expected: 0)
        var highlighted = frame(of: page, at: 160)
        for y in 40..<60 { highlighted[y] = highlighted[y].map { $0 ^ 0x0020_2020 } }
        _ = stitch.add(scrollFrame(highlighted).profile, expected: 60)
        expect(stitch.lastOffset, 60, "a highlighted block in the overlap still lands at the true offset")
    }

    static func lost() {
        let (image, steps) = stitch([0, 40, 300, 100])
        expect(steps[2], .lost, "a jump past the frame matches nowhere")
        expect(
            steps[3], .extended(keep: 200 - footer, rows: (viewport - footer - 60)..<viewport),
            "a frame that overlaps the last one goes on")
        expect(firstDifference(image, expectedImage(through: 100)), nil, "without a gap")
    }

    static func cap() {
        let (image, steps) = stitch([0, 50, 100, 150], cap: 230)
        expect(image.count, 210, "the stitch stops before the cap")
        expect(steps.last, .full, "and says so")
    }

    static func file() {
        guard let file = ScrollStitchFile(width: width) else { return expect(false, true, "the stitch file opens") }
        var stitch = ScrollStitch(cap: 10_000)
        let end = page.count - viewport
        var last = 0
        for offset in [0, 30, 75, 140, 210, 300, 390, 470, 540, 620, 700, end] {
            let shown = scrollFrame(frame(of: page, at: offset))
            let step = stitch.add(shown.profile, expected: offset - last)
            last = offset
            expect(file.write(step, of: shown), true, "the file takes the step's rows")
        }
        guard let image = file.image(height: stitch.height, space: space), let data = image.dataProvider?.data as Data?
        else { return expect(false, true, "the stitch file maps an image") }
        let rows = data.withUnsafeBytes { bytes in
            (0..<image.height).map { y in
                (0..<width).map { bytes.load(fromByteOffset: y * image.bytesPerRow + $0 * 4, as: UInt32.self) }
            }
        }
        expect(firstDifference(rows, expectedImage(through: end)), nil, "the file holds the same rows as the stitch")
        expect(
            file.write(.started(rows: 0..<1), of: scrollFrame(frame(of: page, at: 0))), false, "a closed file takes no more rows")
    }
}
