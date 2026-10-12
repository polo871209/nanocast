import CoreGraphics

struct PixelRect: Hashable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(spanning a: PixelPoint, _ b: PixelPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    init(enclosing rect: CGRect) {
        let minX = Int(rect.minX.rounded(.down))
        let minY = Int(rect.minY.rounded(.down))
        self.init(
            x: minX, y: minY, width: Int(rect.maxX.rounded(.up)) - minX,
            height: Int(rect.maxY.rounded(.up)) - minY)
    }

    var minX: Int { x }
    var minY: Int { y }
    var maxX: Int { x + width }
    var maxY: Int { y + height }
    var isEmpty: Bool { width <= 0 || height <= 0 }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    func contains(_ point: PixelPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    func contains(_ rect: PixelRect) -> Bool {
        rect.minX >= minX && rect.maxX <= maxX && rect.minY >= minY && rect.maxY <= maxY
    }

    func intersection(_ other: PixelRect) -> PixelRect? {
        let left = max(minX, other.minX)
        let top = max(minY, other.minY)
        let right = min(maxX, other.maxX)
        let bottom = min(maxY, other.maxY)
        guard right > left, bottom > top else { return nil }
        return PixelRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
