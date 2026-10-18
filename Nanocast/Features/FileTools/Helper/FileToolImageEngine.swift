import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated enum FileToolImageEngine {
    private static let defaultQuality = 0.9
    private static let minimumFitEdge = 16

    static func run(_ request: FileToolRequest) throws {
        guard let source = request.sources.first, let format = request.imageFormat else {
            throw FileToolEngine.Failure.unsupported
        }
        let decoded = try decode(source, option: request.option)
        let image = format.dropsTransparency ? try flattened(decoded.image) : decoded.image
        let properties = outputProperties(request, format: format, source: decoded.properties)
        if request.kind == .compressImageToSize, let target = request.parameters.targetBytes {
            let data = try fit(image, format: format, properties: properties, within: target)
            try data.write(to: request.destination)
            return
        }
        try write(image, as: format, properties: properties, to: request.destination)
    }

    static func decode(_ source: URL, option: FileToolOption?) throws -> Decoded {
        let isVector = UTType(filenameExtension: source.pathExtension)?.conforms(to: .svg) == true
        return isVector ? try rasterizeVector(source, option: option) : try decodeRaster(source, option: option)
    }

    /// Searches the quality first, then scales down, until the encoded file fits.
    private static func fit(
        _ image: CGImage, format: FileToolImageFormat, properties: [CFString: Any], within target: Int
    ) throws -> Data {
        var current = image
        while current.width > minimumFitEdge, current.height > minimumFitEdge {
            var low = 0.05
            var high = 0.95
            var best: Data?
            for _ in 0..<7 {
                let quality = (low + high) / 2
                let data = try encode(current, as: format, properties: properties, quality: quality)
                if data.count <= target {
                    best = data
                    low = quality
                } else {
                    high = quality
                }
            }
            if let best { return best }
            let smallest = try encode(current, as: format, properties: properties, quality: 0.05)
            if smallest.count <= target { return smallest }
            current = try scaled(current, by: 0.75)
        }
        throw FileToolEngine.Failure.unwritable
    }

    private static func encode(
        _ image: CGImage, as format: FileToolImageFormat, properties: [CFString: Any], quality: Double
    ) throws -> Data {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(data as CFMutableData, format.identifier as CFString, 1, nil)
        else { throw FileToolEngine.Failure.unwritable }
        var options = properties
        options[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FileToolEngine.Failure.unwritable }
        return data as Data
    }

    private static func scaled(_ image: CGImage, by factor: Double) throws -> CGImage {
        let width = max(Int(Double(image.width) * factor), 1)
        let height = max(Int(Double(image.height) * factor), 1)
        return try draw(width: width, height: height) { context, rect in
            context.interpolationQuality = .high
            context.draw(image, in: rect)
        }
    }

    struct Decoded {
        let image: CGImage
        let properties: [CFString: Any]
    }

    private static func decodeRaster(_ url: URL, option: FileToolOption?) throws -> Decoded {
        guard
            let source = CGImageSourceCreateWithURL(
                url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw FileToolEngine.Failure.unreadable }
        let longest = max(width, height)
        var edge = longest
        if case .longestEdge(let longestEdge)? = option { edge = min(longestEdge, longest) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: edge
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FileToolEngine.Failure.unreadable
        }
        return Decoded(image: image, properties: properties)
    }

    private static func rasterizeVector(_ url: URL, option: FileToolOption?) throws -> Decoded {
        guard let vector = NSImage(contentsOf: url) else { throw FileToolEngine.Failure.unreadable }
        let size = vector.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { throw FileToolEngine.Failure.unreadable }
        let scale: CGFloat
        switch option {
        case .longestEdge(let edge)?: scale = CGFloat(edge) / longest
        case .scale(let factor)?: scale = CGFloat(factor)
        default: scale = 1
        }
        let width = max(Int((size.width * scale).rounded()), 1)
        let height = max(Int((size.height * scale).rounded()), 1)
        let image = try draw(width: width, height: height) { _, rect in
            vector.draw(in: rect)
        }
        return Decoded(image: image, properties: [:])
    }

    private static func flattened(_ image: CGImage) throws -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        return try draw(width: image.width, height: image.height) { context, rect in
            context.setFillColor(.white)
            context.fill(rect)
            context.draw(image, in: rect)
        }
    }

    private static func draw(width: Int, height: Int, _ body: (CGContext, CGRect) -> Void) throws -> CGImage {
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw FileToolEngine.Failure.unwritable }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        body(context, CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.current = previous
        guard let image = context.makeImage() else { throw FileToolEngine.Failure.unwritable }
        return image
    }

    private static func outputProperties(
        _ request: FileToolRequest, format: FileToolImageFormat, source: [CFString: Any]
    ) -> [CFString: Any] {
        var properties: [CFString: Any] = [:]
        if format.isLossy {
            var quality = defaultQuality
            if case .quality(let level)? = request.option { quality = level.compression }
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        guard format != .pdf, request.kind != .stripMetadata else { return properties }
        properties[kCGImagePropertyOrientation] = 1
        for key in [kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
            if let value = source[key] { properties[key] = value }
        }
        if var exif = source[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            properties[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = source[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        return properties
    }

    static func write(
        _ image: CGImage, as format: FileToolImageFormat, properties: [CFString: Any] = [:], to url: URL
    ) throws {
        guard
            let destination = CGImageDestinationCreateWithURL(url as CFURL, format.identifier as CFString, 1, nil)
        else { throw FileToolEngine.Failure.unwritable }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FileToolEngine.Failure.unwritable }
    }
}
