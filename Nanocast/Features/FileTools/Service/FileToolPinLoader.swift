import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated enum FileToolPinLoader {
    struct Pin: Sendable {
        let image: CGImage
        let scale: CGFloat
    }

    @concurrent
    static func load(_ url: URL, fitting bounds: CGSize, backingScale: CGFloat) async -> Pin? {
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .svg) == true {
            return await vector(url, fitting: bounds, backingScale: backingScale)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            var width = properties[kCGImagePropertyPixelWidth] as? Double,
            var height = properties[kCGImagePropertyPixelHeight] as? Double, width > 0, height > 0
        else { return nil }
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        let points = 72 / max(properties[kCGImagePropertyDPIWidth] as? Double ?? 72, 1)
        let size = fitted(CGSize(width: width * points, height: height * points), in: bounds)
        let edge = min(max(size.width, size.height) * backingScale, max(width, height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(edge.rounded())
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Pin(image: image, scale: CGFloat(image.width) / size.width)
    }

    @MainActor
    private static func vector(_ url: URL, fitting bounds: CGSize, backingScale: CGFloat) -> Pin? {
        guard let vector = NSImage(contentsOf: url), vector.size.width > 0, vector.size.height > 0 else { return nil }
        let size = fitted(vector.size, in: bounds)
        var rect = CGRect(origin: .zero, size: CGSize(width: size.width * backingScale, height: size.height * backingScale))
        guard let image = vector.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return Pin(image: image, scale: CGFloat(image.width) / size.width)
    }

    private static func fitted(_ size: CGSize, in bounds: CGSize) -> CGSize {
        let fit = min(1, bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
    }
}
