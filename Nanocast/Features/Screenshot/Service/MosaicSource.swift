import CoreGraphics
import CoreImage

struct MosaicSource: Sendable {
    let pixelated: CGImage
    let blurred: CGImage
    let bounds: CGRect

    init?(screen: CGImage, window: WindowShot?, block: Int, blurBlock: Int) {
        let bounds = CGRect(x: 0, y: 0, width: screen.width, height: screen.height)
        guard let pixelated = Self.shrunk(screen, window: window, bounds: bounds, by: block),
            let small = Self.shrunk(screen, window: window, bounds: bounds, by: blurBlock),
            let blurred = Self.blurred(small)
        else { return nil }
        self.pixelated = pixelated
        self.blurred = blurred
        self.bounds = bounds
    }

    func image(for effect: AnnotationStyle.MosaicEffect) -> CGImage {
        effect == .pixelate ? pixelated : blurred
    }

    private static func shrunk(_ screen: CGImage, window: WindowShot?, bounds: CGRect, by block: Int) -> CGImage? {
        let width = max((screen.width + block - 1) / block, 1)
        let height = max((screen.height + block - 1) / block, 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / bounds.width, y: -CGFloat(height) / bounds.height)
        context.drawUpright(screen, in: bounds)
        if let window, let image = window.image { context.drawUpright(image, in: window.frame.cgRect) }
        return context.makeImage()
    }

    private static let context = CIContext()

    private static func blurred(_ image: CGImage) -> CGImage? {
        let source = CIImage(cgImage: image)
        let blurred = source.clampedToExtent().applyingGaussianBlur(sigma: 2).cropped(to: source.extent)
        return context.createCGImage(blurred, from: source.extent)
    }
}
