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

    static func extract(at url: URL) async throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unreadable }
        return try await extract(from: image)
    }

    static func extract(from image: CGImage) async throws -> String {
        var text = ""
        let columns = spans(over: image.width)
        for row in spans(over: image.height) {
            for column in columns {
                try Task.checkCancellation()
                let rect = CGRect(
                    x: column.pixels.lowerBound, y: row.pixels.lowerBound,
                    width: column.pixels.count, height: row.pixels.count)
                guard let tile = image.cropping(to: rect) else { continue }
                for paragraph in try await paragraphs(in: tile, at: rect.origin, keeping: column.owned, row.owned) {
                    let separator = text.isEmpty ? "" : "\n"
                    let room = ClipboardTextExtractor.maximumTextBytes - text.utf8.count - separator.utf8.count
                    guard room > 0 else { return text }
                    text += separator + prefix(of: paragraph, fitting: room)
                }
            }
        }
        return text
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

    private static func paragraphs(
        in tile: CGImage, at origin: CGPoint, keeping columns: Range<Double>, _ rows: Range<Double>
    ) async throws -> [String] {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.minimumTextHeightFraction = 0
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        guard let document = try await request.perform(on: tile).first?.document else { return [] }
        let size = CGSize(width: tile.width, height: tile.height)
        return document.paragraphs.compactMap { paragraph in
            let lines = paragraph.lines.filter { line in
                let box = line.boundingBox.toImageCoordinates(size, origin: .upperLeft)
                return columns.contains(origin.x + box.midX) && rows.contains(origin.y + box.midY)
            }
            guard !lines.isEmpty else { return nil }
            guard lines.count < paragraph.lines.count else { return paragraph.transcript }
            return lines.map(\.transcript).joined(separator: " ")
        }
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
