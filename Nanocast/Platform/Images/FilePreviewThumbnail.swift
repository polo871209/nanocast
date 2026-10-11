import AppKit
import QuickLookThumbnailing

enum FilePreviewThumbnail {
    private static let cache = ThumbnailCache(
        rowBytes: 8 * 1024 * 1024, previewBytes: 32 * 1024 * 1024)

    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.cached(url, maxPixel: maxPixel)
    }

    static func purgePreviews() {
        cache.purgePreviews()
    }

    static func loadAsync(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: maxPixel, height: maxPixel), scale: 2,
            representationTypes: .all)
        let rendered = try? await QLThumbnailGenerator.shared.generateBestRepresentation(
            for: request)
        guard let cgImage = rendered?.cgImage else { return nil }
        let image = NSImage(
            cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.store(
            image, for: url, maxPixel: maxPixel, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}
