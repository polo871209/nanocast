import Foundation

struct PixelPoint: Hashable, Sendable {
    var x: Int
    var y: Int

    func clamped(to bounds: PixelRect) -> PixelPoint {
        PixelPoint(x: min(max(x, bounds.minX), bounds.maxX), y: min(max(y, bounds.minY), bounds.maxY))
    }
}
