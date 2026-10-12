import CoreGraphics

enum ScreenshotRenderer {
    static func image(
        of area: PixelRect, on display: CapturedDisplay, window: WindowShot?, annotations: [Annotation],
        painter: AnnotationPainter
    ) -> CGImage? {
        let exact = window?.exactImage(for: area, within: display.bounds)
        if annotations.isEmpty {
            if let exact { return exact }
            if window?.image == nil { return display.image.cropping(to: area.cgRect) }
        }
        guard
            let context = CGContext(
                data: nil, width: area.width, height: area.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace(of: display.image),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(area.height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: CGFloat(-area.x), y: CGFloat(-area.y))
        if let exact {
            context.drawUpright(exact, in: area.cgRect)
        } else {
            if let screen = display.image.cropping(to: area.cgRect) { context.drawUpright(screen, in: area.cgRect) }
            if let window, let image = window.image { context.drawUpright(image, in: window.frame.cgRect) }
        }
        painter.paint(annotations, in: context, area: area.cgRect)
        return context.makeImage()
    }

    /// A crop shares the frozen screen's pixels, so an image that outlives the capture copies its own.
    static func ownCopy(of image: CGImage) -> CGImage? {
        guard
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace(of: image),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func colorSpace(of image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb, space.supportsOutput { return space }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }
}
