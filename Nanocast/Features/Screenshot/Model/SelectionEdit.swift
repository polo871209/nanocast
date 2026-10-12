import Foundation

struct SelectionEdit: Sendable {
    enum Kind: Equatable, Sendable {
        case draw
        case move
        case resize(SelectionHandle)
    }

    let kind: Kind
    private(set) var area: PixelRect
    private(set) var hasMoved = false
    private let start: PixelRect
    private let bounds: PixelRect
    private let press: PixelPoint
    private let slop: Int
    private var anchor: PixelPoint
    private var last: PixelPoint

    init(pressAt point: PixelPoint, area current: PixelRect?, bounds: PixelRect, reach: Int, slop: Int) {
        let press = point.clamped(to: bounds)
        if let current, let handle = SelectionHandle.at(point, of: current, reach: reach) {
            kind = .resize(handle)
            area = current
        } else if let current, current.contains(point) {
            kind = .move
            area = current
        } else {
            kind = .draw
            area = PixelRect(x: press.x, y: press.y, width: 0, height: 0)
        }
        start = area
        self.bounds = bounds
        self.press = press
        self.slop = slop
        anchor = press
        last = point
    }

    mutating func drag(to pointer: PixelPoint, square: Bool, panning: Bool) {
        defer { last = pointer }
        if !hasMoved {
            guard max(abs(pointer.x - press.x), abs(pointer.y - press.y)) > slop else { return }
            hasMoved = true
        }
        switch kind {
        case .draw where panning:
            let moved = Self.moved(area, dx: pointer.x - last.x, dy: pointer.y - last.y, within: bounds)
            anchor.x += moved.x - area.x
            anchor.y += moved.y - area.y
            area = moved
        case .draw:
            area = Self.drawn(from: anchor, to: pointer, square: square, within: bounds)
        case .move:
            area = Self.moved(start, dx: pointer.x - press.x, dy: pointer.y - press.y, within: bounds)
        case .resize(let handle):
            area = resized(by: handle, to: pointer.clamped(to: bounds), square: square)
        }
    }

    static func drawn(
        from anchor: PixelPoint, to pointer: PixelPoint, square: Bool, within bounds: PixelRect
    )
        -> PixelRect
    {
        let end = pointer.clamped(to: bounds)
        guard square else { return PixelRect(spanning: anchor, end) }
        let towardRight = end.x >= anchor.x
        let towardBottom = end.y >= anchor.y
        let room = min(
            towardRight ? bounds.maxX - anchor.x : anchor.x - bounds.minX,
            towardBottom ? bounds.maxY - anchor.y : anchor.y - bounds.minY)
        let side = min(max(abs(end.x - anchor.x), abs(end.y - anchor.y)), room)
        let corner = PixelPoint(
            x: anchor.x + (towardRight ? side : -side), y: anchor.y + (towardBottom ? side : -side))
        return PixelRect(spanning: anchor, corner)
    }

    static func moved(_ rect: PixelRect, dx: Int, dy: Int, within bounds: PixelRect) -> PixelRect {
        var moved = rect
        moved.x = min(max(rect.x + dx, bounds.minX), bounds.maxX - rect.width)
        moved.y = min(max(rect.y + dy, bounds.minY), bounds.maxY - rect.height)
        return moved
    }

    static func grown(_ rect: PixelRect, dx: Int, dy: Int, within bounds: PixelRect) -> PixelRect {
        var grown = rect
        grown.width = min(max(rect.width + dx, 1), bounds.maxX - rect.x)
        grown.height = min(max(rect.height + dy, 1), bounds.maxY - rect.y)
        return grown
    }

    private func resized(by handle: SelectionHandle, to pointer: PixelPoint, square: Bool) -> PixelRect {
        switch handle {
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            let fixed = Self.opposite(handle).point(on: start)
            return Self.drawn(from: fixed, to: pointer, square: square, within: bounds)
        case .left, .right:
            let fixed = handle == .left ? start.maxX : start.minX
            return PixelRect(
                x: min(fixed, pointer.x), y: start.y, width: abs(fixed - pointer.x), height: start.height)
        case .top, .bottom:
            let fixed = handle == .top ? start.maxY : start.minY
            return PixelRect(
                x: start.x, y: min(fixed, pointer.y), width: start.width, height: abs(fixed - pointer.y))
        }
    }

    private static func opposite(_ handle: SelectionHandle) -> SelectionHandle {
        switch handle {
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
}
