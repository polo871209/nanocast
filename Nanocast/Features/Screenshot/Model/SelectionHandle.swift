import CoreGraphics

enum SelectionHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var opposite: SelectionHandle {
        switch self {
        case .topLeft: return .bottomRight
        case .top: return .bottom
        case .topRight: return .bottomLeft
        case .right: return .left
        case .bottomRight: return .topLeft
        case .bottom: return .top
        case .bottomLeft: return .topRight
        case .left: return .right
        }
    }

    init(pointing direction: CGVector) {
        let clockwise: [SelectionHandle] = [.right, .bottomRight, .bottom, .bottomLeft, .left, .topLeft, .top, .topRight]
        let octant = Int((atan2(direction.dy, direction.dx) / (.pi / 4)).rounded())
        self = clockwise[(octant % 8 + 8) % 8]
    }

    func point(on rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    func point(on rect: PixelRect) -> PixelPoint {
        let midX = rect.minX + rect.width / 2
        let midY = rect.minY + rect.height / 2
        switch self {
        case .topLeft: return PixelPoint(x: rect.minX, y: rect.minY)
        case .top: return PixelPoint(x: midX, y: rect.minY)
        case .topRight: return PixelPoint(x: rect.maxX, y: rect.minY)
        case .right: return PixelPoint(x: rect.maxX, y: midY)
        case .bottomRight: return PixelPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return PixelPoint(x: midX, y: rect.maxY)
        case .bottomLeft: return PixelPoint(x: rect.minX, y: rect.maxY)
        case .left: return PixelPoint(x: rect.minX, y: midY)
        }
    }

    static func at(_ point: PixelPoint, of rect: PixelRect, reach: Int) -> SelectionHandle? {
        let left = abs(point.x - rect.minX)
        let right = abs(point.x - rect.maxX)
        let top = abs(point.y - rect.minY)
        let bottom = abs(point.y - rect.maxY)
        let nearLeft = left <= reach && left <= right
        let nearRight = right <= reach && right < left
        let nearTop = top <= reach && top <= bottom
        let nearBottom = bottom <= reach && bottom < top
        let alongX = point.x >= rect.minX - reach && point.x <= rect.maxX + reach
        let alongY = point.y >= rect.minY - reach && point.y <= rect.maxY + reach
        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return alongY ? .left : nil
        case (_, true, _, _): return alongY ? .right : nil
        case (_, _, true, _): return alongX ? .top : nil
        case (_, _, _, true): return alongX ? .bottom : nil
        default: return nil
        }
    }
}
