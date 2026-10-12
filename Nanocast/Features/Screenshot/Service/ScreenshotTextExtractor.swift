import Foundation
import ImageIO
import Vision

nonisolated enum ScreenshotTextExtractor {
    private static let tileSide = 2560
    private static let tileOverlap = 256

    enum Failure: Error { case unreadable }

    private struct Span {
        let pixels: Range<Int>
        let owned: Range<Double>
    }

    private struct Tile {
        let column: Span
        let row: Span

        var rect: CGRect {
            CGRect(
                x: column.pixels.lowerBound, y: row.pixels.lowerBound,
                width: column.pixels.count, height: row.pixels.count)
        }
    }

    static func extract(at url: URL) async throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unreadable }
        return try await extract(from: image)
    }

    static func extract(from image: CGImage) async throws -> String {
        let columns = spans(over: image.width)
        let tiles = spans(over: image.height).flatMap { row in columns.map { Tile(column: $0, row: row) } }
        return try await withThrowingTaskGroup(of: (index: Int, paragraphs: [String]).self) { group in
            var text = ""
            var started = 0
            var appended = 0
            var finished: [Int: [String]] = [:]
            while appended < tiles.count {
                while started < tiles.count, started - appended - finished.count < 4 {
                    let index = started
                    group.addTask { (index, try await paragraphs(in: image, on: tiles[index])) }
                    started += 1
                }
                guard let result = try await group.next() else { break }
                finished[result.index] = result.paragraphs
                while let paragraphs = finished.removeValue(forKey: appended) {
                    appended += 1
                    guard append(paragraphs, to: &text) else {
                        group.cancelAll()
                        return text
                    }
                }
            }
            return text
        }
    }

    // Vision misses most text on an image over about 4,000 px a side, as measured on macOS 27.
    private static func spans(over length: Int) -> [Span] {
        let starts = Array(stride(from: 0, to: max(1, length - tileOverlap), by: tileSide - tileOverlap))
        return starts.enumerated().map { index, start in
            let end = min(start + tileSide, length)
            let lower = index == 0 ? -Double.infinity : Double(start + tileOverlap / 2)
            let upper = index == starts.count - 1 ? Double.infinity : Double(end - tileOverlap / 2)
            return Span(pixels: start..<end, owned: lower..<upper)
        }
    }

    private static func paragraphs(in image: CGImage, on tile: Tile) async throws -> [String] {
        try Task.checkCancellation()
        let rect = tile.rect
        guard let cropped = image.cropping(to: rect) else { return [] }
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.minimumTextHeightFraction = 0
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        guard let document = try await request.perform(on: cropped).first?.document else { return [] }
        let size = CGSize(width: cropped.width, height: cropped.height)
        return document.paragraphs.compactMap { paragraph in
            let lines = paragraph.lines.filter { line in
                let box = line.boundingBox.toImageCoordinates(size, origin: .upperLeft)
                return tile.column.owned.contains(rect.minX + box.midX) && tile.row.owned.contains(rect.minY + box.midY)
            }
            guard !lines.isEmpty else { return nil }
            guard lines.count < paragraph.lines.count else { return paragraph.transcript }
            return lines.map(\.transcript).joined(separator: " ")
        }
    }

    private static func append(_ paragraphs: [String], to text: inout String) -> Bool {
        for paragraph in paragraphs {
            let separator = text.isEmpty ? "" : "\n"
            let room = ClipboardTextExtractor.maximumTextBytes - text.utf8.count - separator.utf8.count
            guard room > 0 else { return false }
            text += separator + prefix(of: paragraph, fitting: room)
        }
        return true
    }

    private static func prefix(of text: String, fitting bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var prefix = ""
        for character in text {
            guard prefix.utf8.count + character.utf8.count <= bytes else { break }
            prefix.append(character)
        }
        return prefix
    }
}
