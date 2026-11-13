import CoreGraphics

struct CapturedDisplay: Identifiable, Sendable {
    let id: UInt32
    let image: CGImage
    let frame: CGRect
    let quartzFrame: CGRect

    var scale: CGFloat { CGFloat(image.width) / frame.width }
    var bounds: PixelRect { PixelRect(x: 0, y: 0, width: image.width, height: image.height) }

    func points(_ rect: PixelRect) -> CGRect {
        CGRect(
            x: CGFloat(rect.x) / scale, y: CGFloat(rect.y) / scale, width: CGFloat(rect.width) / scale,
            height: CGFloat(rect.height) / scale)
    }

    func gridPoint(_ point: CGPoint) -> PixelPoint {
        PixelPoint(x: Int((point.x * scale).rounded()), y: Int((point.y * scale).rounded()))
    }

    func pixel(_ point: CGPoint) -> PixelPoint {
        PixelPoint(x: Int((point.x * scale).rounded(.down)), y: Int((point.y * scale).rounded(.down)))
    }

    func quartzPoint(_ point: PixelPoint) -> CGPoint {
        CGPoint(
            x: quartzFrame.minX + CGFloat(point.x) / scale, y: quartzFrame.minY + CGFloat(point.y) / scale)
    }
}
