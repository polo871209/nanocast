import AppKit
import ImageIO
import PDFKit

nonisolated enum FileToolPDFEngine {
    private static let renderScale: CGFloat = 2

    static func run(_ request: FileToolRequest) throws {
        switch request.kind {
        case .combinePDFs: try combine(request)
        case .imagesToPDF: try imagesToPDF(request)
        case .splitPDF: try split(request)
        case .extractPages: try extractPages(request)
        case .compressPDF: try compress(request)
        case .pdfToImages: try renderPages(request)
        case .pdfToText: try text(request)
        default: throw FileToolEngine.Failure.unsupported
        }
    }

    private static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
            throw FileToolEngine.Failure.unreadable
        }
        return document
    }

    private static func save(_ document: PDFDocument, to url: URL, options: [PDFDocumentWriteOption: Any] = [:]) throws {
        guard document.write(to: url, withOptions: options) else { throw FileToolEngine.Failure.unwritable }
    }

    private static func combine(_ request: FileToolRequest) throws {
        let combined = PDFDocument()
        for (index, source) in request.sources.enumerated() {
            let document = try open(source)
            for page in 0..<document.pageCount {
                guard let copy = document.page(at: page)?.copy() as? PDFPage else { continue }
                combined.insert(copy, at: combined.pageCount)
            }
            FileToolEngine.report(Double(index + 1) / Double(request.sources.count))
        }
        try save(combined, to: request.destination)
    }

    private static func imagesToPDF(_ request: FileToolRequest) throws {
        guard let consumer = CGDataConsumer(url: request.destination as CFURL),
            let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else { throw FileToolEngine.Failure.unwritable }
        for (index, source) in request.sources.enumerated() {
            try autoreleasepool {
                let decoded = try FileToolImageEngine.decode(source, option: nil)
                let dpi = decoded.properties[kCGImagePropertyDPIWidth] as? Double ?? 72
                let points = 72 / max(dpi, 1)
                var box = CGRect(
                    x: 0, y: 0, width: Double(decoded.image.width) * points,
                    height: Double(decoded.image.height) * points)
                context.beginPage(mediaBox: &box)
                context.draw(decoded.image, in: box)
                context.endPage()
            }
            FileToolEngine.report(Double(index + 1) / Double(request.sources.count))
        }
        context.closePDF()
    }

    private static func split(_ request: FileToolRequest) throws {
        guard let source = request.sources.first else { throw FileToolEngine.Failure.unsupported }
        let document = try open(source)
        let folder = try makeFolder(request.destination)
        let stem = source.deletingPathExtension().lastPathComponent
        for index in 0..<document.pageCount {
            try autoreleasepool {
                let single = PDFDocument()
                guard let page = document.page(at: index)?.copy() as? PDFPage else { return }
                single.insert(page, at: 0)
                try save(single, to: folder.appendingPathComponent(pageName(stem, index, of: document.pageCount, "pdf")))
            }
            FileToolEngine.report(Double(index + 1) / Double(document.pageCount))
        }
    }

    private static func extractPages(_ request: FileToolRequest) throws {
        guard let source = request.sources.first else { throw FileToolEngine.Failure.unsupported }
        let document = try open(source)
        let extracted = PDFDocument()
        for number in request.parameters.pages where number <= document.pageCount {
            guard let page = document.page(at: number - 1)?.copy() as? PDFPage else { continue }
            extracted.insert(page, at: extracted.pageCount)
        }
        guard extracted.pageCount > 0 else { throw FileToolEngine.Failure.unreadable }
        try save(extracted, to: request.destination)
    }

    private static func compress(_ request: FileToolRequest) throws {
        guard let source = request.sources.first else { throw FileToolEngine.Failure.unsupported }
        try save(
            try open(source), to: request.destination,
            options: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true])
    }

    private static func renderPages(_ request: FileToolRequest) throws {
        guard let source = request.sources.first, case .pageFormat(let format)? = request.option else {
            throw FileToolEngine.Failure.unsupported
        }
        let document = try open(source)
        let folder = try makeFolder(request.destination)
        let stem = source.deletingPathExtension().lastPathComponent
        for index in 0..<document.pageCount {
            try autoreleasepool {
                guard let page = document.page(at: index) else { return }
                let image = try render(page)
                let name = pageName(stem, index, of: document.pageCount, format.fileExtension)
                try FileToolImageEngine.write(
                    image, as: format, properties: format.isLossy ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:],
                    to: folder.appendingPathComponent(name))
            }
            FileToolEngine.report(Double(index + 1) / Double(document.pageCount))
        }
    }

    private static func render(_ page: PDFPage) throws -> CGImage {
        let bounds = page.bounds(for: .cropBox)
        let rotated = page.rotation % 180 != 0
        let size = rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        let width = max(Int((size.width * renderScale).rounded()), 1)
        let height = max(Int((size.height * renderScale).rounded()), 1)
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw FileToolEngine.Failure.unwritable }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: renderScale, y: renderScale)
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else { throw FileToolEngine.Failure.unwritable }
        return image
    }

    private static func text(_ request: FileToolRequest) throws {
        guard let source = request.sources.first else { throw FileToolEngine.Failure.unsupported }
        let document = try open(source)
        var pages: [String] = []
        for index in 0..<document.pageCount {
            autoreleasepool { pages.append(document.page(at: index)?.string ?? "") }
            FileToolEngine.report(Double(index + 1) / Double(document.pageCount))
        }
        try Data(pages.joined(separator: "\n\n").utf8).write(to: request.destination)
    }

    private static func makeFolder(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private static func pageName(_ stem: String, _ index: Int, of count: Int, _ fileExtension: String) -> String {
        let digits = String(count).count
        let number = String(index + 1)
        return "\(stem) \(String(repeating: "0", count: digits - number.count))\(number).\(fileExtension)"
    }
}
