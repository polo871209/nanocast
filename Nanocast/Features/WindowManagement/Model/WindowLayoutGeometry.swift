import CoreGraphics
import Foundation

enum WindowLayoutGeometry {
    static let minimumLength: CGFloat = 1

    static func box(_ screen: WindowPlacementEngine.Screen, gap: CGFloat) -> CGRect {
        WindowPlacementEngine.canvas(
            screen.visibleFrame,
            gap: WindowPlacementEngine.sanitizedGap(gap, in: screen.visibleFrame))
    }

    static func resolve(
        _ entry: WindowLayoutEntry, on screen: WindowPlacementEngine.Screen, gap: CGFloat
    ) -> CGRect? {
        let box = box(screen, gap: gap)
        guard box.width > 0, box.height > 0 else { return nil }

        let size = CGSize(
            width: length(box.width * fraction(entry.widthFraction), in: box.width),
            height: length(box.height * fraction(entry.heightFraction), in: box.height))

        let placed = entry.anchor.placement.place(size, in: box)
            .offsetBy(dx: nudge(entry.offset.x), dy: nudge(entry.offset.y))
        return WindowPlacementEngine.rounded(WindowPlacementEngine.clamped(placed, into: box))
    }

    struct Capture: Equatable, Sendable {
        var widthFraction: CGFloat
        var heightFraction: CGFloat
        var anchor: WindowLayoutAnchor
        var offset: CGPoint
    }

    static func describe(
        _ frame: CGRect, on screen: WindowPlacementEngine.Screen, gap: CGFloat
    ) -> Capture {
        let box = box(screen, gap: gap)
        guard box.width > 0, box.height > 0 else {
            return Capture(widthFraction: 1, heightFraction: 1, anchor: .center, offset: .zero)
        }

        let size = CGSize(
            width: min(frame.width, box.width), height: min(frame.height, box.height))
        let horizontal = nearestAxis(
            frame.minX, boxMin: box.minX, boxLength: box.width, length: size.width)
        let vertical = nearestAxis(
            frame.minY, boxMin: box.minY, boxLength: box.height, length: size.height)
        let anchor = WindowLayoutAnchor.named(horizontal: horizontal, vertical: vertical)
        let origin = anchor.placement.place(size, in: box).origin

        return Capture(
            widthFraction: size.width / box.width, heightFraction: size.height / box.height,
            anchor: anchor,
            offset: CGPoint(x: frame.minX - origin.x, y: frame.minY - origin.y))
    }

    static func entry(
        bundleID: String, display: WindowLayoutDisplay, frame: CGRect,
        on screen: WindowPlacementEngine.Screen
    ) -> WindowLayoutEntry {
        let capture = describe(frame, on: screen, gap: 0)
        return WindowLayoutEntry(
            bundleID: bundleID, display: display, widthFraction: capture.widthFraction,
            heightFraction: capture.heightFraction, anchor: capture.anchor, offset: capture.offset)
    }

    private static func nearestAxis(
        _ position: CGFloat, boxMin: CGFloat, boxLength: CGFloat, length: CGFloat
    ) -> WindowPlacementEngine.Anchor.Axis {
        let free = boxLength - length
        let candidates: [(WindowPlacementEngine.Anchor.Axis, CGFloat)] = [
            (.center, boxMin + free / 2), (.min, boxMin), (.max, boxMin + free)
        ]
        var best = candidates[0]
        for candidate in candidates.dropFirst()
        where abs(position - candidate.1) < abs(position - best.1) {
            best = candidate
        }
        return best.0
    }

    private static func fraction(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        let range = WindowLayoutEntry.fractionRange
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func length(_ value: CGFloat, in available: CGFloat) -> CGFloat {
        min(available, max(minimumLength, value))
    }

    private static func nudge(_ value: CGFloat) -> CGFloat { value.isFinite ? value : 0 }
}
