import AppKit
import Synchronization
import UniformTypeIdentifiers

struct IconCacheGeneration {
    private(set) var value = 0

    mutating func invalidate() {
        value &+= 1
    }

    func publish<Value>(_ item: Value, capturedAt generation: Int, store: (Value) -> Void) -> Value {
        if value == generation { store(item) }
        return item
    }
}

@MainActor
@Observable
final class IconStyleSignal {
    private(set) var generation = 0

    fileprivate func bump() { generation &+= 1 }
}

struct IconRequest<Key: Hashable>: Hashable {
    let key: Key
    let generation: Int

    @MainActor
    init(_ key: Key) {
        self.key = key
        self.generation = IconCache.style.generation
    }
}

enum SystemSymbolName {
    // This pair swaps glyphs in Dark, so there the outline is the inverse.
    static func resolve(_ name: String, isDark: Bool) -> String {
        name == "face.smiling" && isDark ? "face.smiling.inverse" : name
    }
}

enum EntryIcon: Hashable, Sendable {
    case file(stamp: Int)
    case symbol(String)
    case contentType(String)
}

struct IconSize: Hashable, Sendable {
    let points: CGFloat
    let scale: CGFloat

    var pixels: Int { Int((points * scale).rounded(.up)) }
}

enum IconCache {
    private final class Cache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    private final class RowImage {
        let size: IconSize
        let image: NSImage

        init(size: IconSize, image: NSImage) {
            self.size = size
            self.image = image
        }
    }

    private final class RowCache: NSCache<NSString, RowImage>, @unchecked Sendable {}

    private static let rowCache: RowCache = {
        let cache = RowCache()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    private static let displayPixel: CGFloat = 48

    private static let cache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    private static let fittedCache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()
    private static let fittedGeneration = Mutex(IconCacheGeneration())

    static func cached(forFile path: String, stamp: Int = 0, size: IconSize? = nil) -> NSImage? {
        let key = fileKey(path, stamp)
        guard let size else { return cache.object(forKey: key) }
        guard let entry = rowCache.object(forKey: key), entry.size == size else { return nil }
        return entry.image
    }
    static func cachedSymbol(named name: String) -> NSImage? {
        cache.object(forKey: symbolKey(name))
    }

    private static let darkSurface = Mutex(true)

    @MainActor static func setDarkSurface(_ isDark: Bool) {
        let changed = darkSurface.withLock { surface -> Bool in
            defer { surface = isDark }
            return surface != isDark
        }
        if changed { invalidateStyled() }
    }

    @MainActor static let style = IconStyleSignal()

    private static let styleGeneration = Mutex(0)

    @MainActor static func observeStyle() { _ = style.generation }

    @MainActor static func invalidateStyled() {
        styleGeneration.withLock { $0 &+= 1 }
        cache.removeAllObjects()
        rowCache.removeAllObjects()
        purgeFitted()
        style.bump()
    }

    /// macOS restyles `NSWorkspace`'s images in place, so these bytes are the only proof it landed.
    static func styleFingerprint() -> Data? {
        let side = 32
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSWorkspace.shared.icon(forFile: styleProbePath)
            .draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let bytes = rep.bitmapData else { return nil }
        return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    private static let styleProbePath = "/System/Library/CoreServices/Finder.app"

    private static func key(_ body: String) -> NSString {
        "\(styleGeneration.withLock { $0 }):\(body)" as NSString
    }

    private static func symbolKey(_ name: String) -> NSString {
        let surface = darkSurface.withLock { $0 } ? "dark" : "light"
        return key("symbol:\(surface):\(name)")
    }

    private struct Decoded: @unchecked Sendable {
        let image: NSImage?
        let cost: Int

        init(image: NSImage?, cost: Int = 0) {
            self.image = image
            self.cost = cost
        }
    }

    static func loadAsync(forFile path: String, stamp: Int = 0, size: IconSize? = nil) async -> NSImage? {
        if let cached = cached(forFile: path, stamp: stamp, size: size) { return cached }
        return await Task.detached(priority: .userInitiated) { () -> Decoded in
            guard FileManager.default.fileExists(atPath: path) else { return Decoded(image: nil) }
            return Decoded(image: icon(forFile: path, stamp: stamp, size: size))
        }.value.image
    }
    static func loadSymbolAsync(named name: String) async -> NSImage? {
        if let cached = cachedSymbol(named: name) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: symbolIcon(named: name))
        }.value.image
    }

    static func icon(forFile path: String, stamp: Int = 0, size: IconSize? = nil) -> NSImage {
        if let size { return rowIcon(forFile: path, stamp: stamp, size: size) }
        let key = fileKey(path, stamp)
        if let cached = cache.object(forKey: key) { return cached }
        let (icon, cost) = downsampled(NSWorkspace.shared.icon(forFile: path))
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    private static func rowIcon(forFile path: String, stamp: Int, size: IconSize) -> NSImage {
        if let warm = cached(forFile: path, stamp: stamp, size: size) { return warm }
        let (image, cost) = autoreleasepool { () -> (NSImage, Int) in
            let (source, sourceCost) = downsampled(NSWorkspace.shared.icon(forFile: path))
            return resized(source, to: size) ?? (source, sourceCost)
        }
        rowCache.setObject(RowImage(size: size, image: image), forKey: fileKey(path, stamp), cost: cost)
        return image
    }

    private static func resized(_ source: NSImage, to size: IconSize) -> (NSImage, Int)? {
        guard size.pixels < Int(displayPixel * 2) else { return nil }
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size.pixels, pixelsHigh: size.pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: size.points, height: size.points)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: rep.size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return (image, rep.bytesPerRow * rep.pixelsHigh)
    }

    static func symbolIcon(named name: String) -> NSImage {
        let key = symbolKey(name)
        if let cached = cache.object(forKey: key) { return cached }

        let side = displayPixel
        let isDark = darkSurface.withLock { $0 }
        let plainInk: CGFloat = isDark ? 1 : 0
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let tile = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 4, dy: 4)
            NSColor.srgbInk(plainInk, alpha: 0.09).setFill()
            NSBezierPath(roundedRect: tile, xRadius: 9, yRadius: 9).fill()

            // A symbol picks its glyph by the drawing appearance, which off-main isn't the surface's.
            NSAppearance(named: isDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                guard
                    let symbol = glyph(
                        named: name, tint: .srgbInk(plainInk, alpha: 0.85), isDark: isDark)
                else { return }
                let size = symbol.size
                symbol.draw(
                    in: NSRect(
                        x: (side - size.width) / 2, y: (side - size.height) / 2,
                        width: size.width, height: size.height))
            }
            return true
        }
        let (icon, cost) = downsampled(image)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    private static func glyph(named name: String, tint: NSColor, isDark: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 21, weight: .medium)
            .applying(.init(paletteColors: [tint]))
        if let symbol = NSImage(
            systemSymbolName: SystemSymbolName.resolve(name, isDark: isDark),
            accessibilityDescription: nil
        )?
        .withSymbolConfiguration(config) {
            return symbol
        }
        guard let asset = NSImage(named: name) else { return nil }
        let assetSize = NSSize(width: 24, height: 24)
        return NSImage(size: assetSize, flipped: false) { rect in
            asset.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    static let appIconExtent: CGFloat = 0.83

    static func fitted(_ source: NSImage, to extent: CGFloat) -> (NSImage, Int) {
        let painted = paintedExtent(source) ?? appIconExtent
        let side = displayPixel * extent / painted
        let inset = (displayPixel - side) / 2
        return rasterized(source, into: NSRect(x: inset, y: inset, width: side, height: side))
    }

    static func contentTypeIcon(_ identifier: String) -> NSImage {
        let key = contentTypeKey(identifier)
        if let cached = cache.object(forKey: key) { return cached }
        let (icon, cost) = downsampled(NSWorkspace.shared.icon(for: UTType(identifier) ?? .item))
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    static func cachedContentTypeIcon(_ identifier: String) -> NSImage? {
        cache.object(forKey: contentTypeKey(identifier))
    }

    static func loadContentTypeIconAsync(_ identifier: String) async -> NSImage? {
        if let cached = cachedContentTypeIcon(identifier) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: contentTypeIcon(identifier))
        }.value.image
    }

    private static func contentTypeKey(_ identifier: String) -> NSString {
        key("type:\(identifier)")
    }

    static func icon(for source: EntryIcon, fileURL: URL) -> NSImage {
        switch source {
        case .file(let stamp): return icon(forFile: fileURL.path, stamp: stamp)
        case .symbol(let name): return symbolIcon(named: name)
        case .contentType(let identifier): return contentTypeIcon(identifier)
        }
    }

    static func cached(_ source: EntryIcon, fileURL: URL, size: IconSize? = nil) -> NSImage? {
        switch source {
        case .file(let stamp): return cached(forFile: fileURL.path, stamp: stamp, size: size)
        case .symbol(let name): return cachedSymbol(named: name)
        case .contentType(let identifier): return cachedContentTypeIcon(identifier)
        }
    }

    static func loadAsync(_ source: EntryIcon, fileURL: URL, size: IconSize? = nil) async -> NSImage? {
        switch source {
        case .file(let stamp): return await loadAsync(forFile: fileURL.path, stamp: stamp, size: size)
        case .symbol(let name): return await loadSymbolAsync(named: name)
        case .contentType(let identifier): return await loadContentTypeIconAsync(identifier)
        }
    }

    static func cachedFitted(forFile path: String) -> NSImage? {
        fittedCache.object(forKey: fittedKey(path))
    }

    static func loadFittedAsync(forFile path: String) async -> NSImage? {
        if let cached = cachedFitted(forFile: path) { return cached }
        let generation = fittedGeneration.withLock { $0.value }
        let decoded = await Task.detached(
            priority: .userInitiated,
            operation: { () -> Decoded in
                guard FileManager.default.fileExists(atPath: path) else {
                    return Decoded(image: nil)
                }
                return fittedIcon(forFile: path)
            }
        ).value
        guard let image = decoded.image, !Task.isCancelled else { return nil }
        return fittedGeneration.withLock { current in
            current.publish(image, capturedAt: generation) { image in
                fittedCache.setObject(image, forKey: fittedKey(path), cost: decoded.cost)
            }
        }
    }

    static func purgeFitted() {
        fittedGeneration.withLock { generation in
            generation.invalidate()
            fittedCache.removeAllObjects()
        }
    }

    private static func fileKey(_ path: String, _ stamp: Int) -> NSString {
        key("file:\(stamp):\(path)")
    }
    private static func fittedKey(_ path: String) -> NSString { key("fit:" + path) }

    private static func fittedIcon(forFile path: String) -> Decoded {
        let (icon, cost) = fittedToArtwork(NSWorkspace.shared.icon(forFile: path))
        return Decoded(image: icon, cost: cost)
    }

    private static func fittedToArtwork(_ source: NSImage) -> (NSImage, Int) {
        fitted(source, to: appIconExtent)
    }

    private static func paintedExtent(_ source: NSImage) -> CGFloat? {
        let pixels = Int(displayPixel * 2)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 32),
            let data = rep.bitmapData,
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        var minX = pixels, maxX = -1, minY = pixels, maxY = -1
        for y in 0..<pixels {
            let row = data.advanced(by: y * rep.bytesPerRow)
            for x in 0..<pixels {
                guard row[x * 4 + 3] >= 16 else {
                    continue
                }
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let side = max(maxX - minX + 1, maxY - minY + 1)
        return CGFloat(side) / CGFloat(pixels)
    }

    private static func downsampled(_ source: NSImage) -> (NSImage, Int) {
        rasterized(
            source, into: NSRect(origin: .zero, size: NSSize(width: displayPixel, height: displayPixel)))
    }

    private static func rasterized(_ source: NSImage, into frame: NSRect) -> (NSImage, Int) {
        let pixels = Int(displayPixel * 2)
        let fallbackCost = Int(displayPixel * displayPixel * 4)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return (source, fallbackCost) }
        rep.size = NSSize(width: displayPixel, height: displayPixel)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return (source, fallbackCost)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        source.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return (image, rep.bytesPerRow * rep.pixelsHigh)
    }
}
