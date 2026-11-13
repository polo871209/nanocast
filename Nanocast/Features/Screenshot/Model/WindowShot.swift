import CoreGraphics

struct WindowShot: Sendable {
    let windowID: UInt32
    let display: UInt32
    let frame: PixelRect
    var image: CGImage?

    func isVisiblePart(_ area: PixelRect, within bounds: PixelRect) -> Bool {
        frame.intersection(bounds) == area
    }

    func exactImage(for area: PixelRect, within bounds: PixelRect) -> CGImage? {
        guard let image, isVisiblePart(area, within: bounds) else { return nil }
        return image.cropping(to: area.cgRect.offsetBy(dx: CGFloat(-frame.x), dy: CGFloat(-frame.y)))
    }
}
