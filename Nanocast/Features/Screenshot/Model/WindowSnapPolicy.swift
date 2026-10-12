import CoreGraphics

enum WindowSnapPolicy {
    struct Target: Equatable, Sendable {
        struct Window: Equatable, Sendable {
            let id: UInt32
            let frame: PixelRect
        }

        let area: PixelRect
        let window: Window?
    }

    static func target(at point: CGPoint, windows: [ScreenWindow], display: CGRect, scale: CGFloat) -> Target {
        let bounds = PixelRect(
            x: 0, y: 0, width: Int((display.width * scale).rounded()), height: Int((display.height * scale).rounded()))
        for window in windows where window.frame.contains(point) {
            let local = window.frame.offsetBy(dx: -display.minX, dy: -display.minY)
            let frame = PixelRect(
                enclosing: CGRect(
                    x: local.minX * scale, y: local.minY * scale, width: local.width * scale,
                    height: local.height * scale))
            if let visible = frame.intersection(bounds) {
                return Target(area: visible, window: Target.Window(id: window.id, frame: frame))
            }
        }
        return Target(area: bounds, window: nil)
    }
}
