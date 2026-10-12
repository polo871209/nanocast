import CoreGraphics

enum AnnotationGeometry {
    static func square(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let side = max(abs(end.x - start.x), abs(end.y - start.y))
        return CGPoint(
            x: start.x + (end.x >= start.x ? side : -side), y: start.y + (end.y >= start.y ? side : -side))
    }

    static func snapped(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx != 0 || dy != 0 else { return end }
        let directions: [CGVector] = [
            CGVector(dx: 1, dy: 0), CGVector(dx: 1, dy: 1), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 1),
            CGVector(dx: -1, dy: 0), CGVector(dx: -1, dy: -1), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: -1)
        ]
        let octant = Int((atan2(dy, dx) / (.pi / 4)).rounded())
        let direction = directions[(octant % 8 + 8) % 8]
        let along = (dx * direction.dx + dy * direction.dy) / (direction.dx * direction.dx + direction.dy * direction.dy)
        return CGPoint(x: start.x + along * direction.dx, y: start.y + along * direction.dy)
    }

    static func arrowOutline(_ segment: Annotation.Segment, width: CGFloat) -> [CGPoint] {
        let length = segment.length
        guard length > 0, width > 0 else { return [] }
        let along = CGVector(dx: (segment.end.x - segment.start.x) / length, dy: (segment.end.y - segment.start.y) / length)
        let across = CGVector(dx: -along.dy, dy: along.dx)
        let headLength = min(width * 4.5, length)
        let headHalf = headLength / 2
        let shaftHalf = min(width / 2, headHalf / 2)
        let tailHalf = shaftHalf * 0.35
        let base = CGPoint(x: segment.end.x - along.dx * headLength, y: segment.end.y - along.dy * headLength)
        func offset(_ point: CGPoint, _ distance: CGFloat) -> CGPoint {
            CGPoint(x: point.x + across.dx * distance, y: point.y + across.dy * distance)
        }
        return [
            offset(segment.start, tailHalf), offset(base, shaftHalf), offset(base, headHalf), segment.end,
            offset(base, -headHalf), offset(base, -shaftHalf), offset(segment.start, -tailHalf)
        ]
    }

    static func textFrame(_ text: String, origin: CGPoint, style: AnnotationStyle, metrics: AnnotationMetrics) -> CGRect {
        CGRect(origin: origin, size: metrics.measureText(printable(text), metrics.textSize(style.textSize)))
    }

    static func stepCircle(at center: CGPoint, style: AnnotationStyle, metrics: AnnotationMetrics) -> CGRect {
        let radius = metrics.textSize(style.textSize) / 2 + metrics.stepInset
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    static func frame(of annotation: Annotation, metrics: AnnotationMetrics) -> CGRect {
        let style = annotation.style
        switch annotation.shape {
        case .rectangle(let rect), .ellipse(let rect):
            let half = metrics.stroke(style.stroke) / 2
            return rect.insetBy(dx: -half, dy: -half)
        case .mosaicBox(let rect):
            return rect
        case .line(let segment):
            return bounds([segment.start, segment.end], outset: metrics.stroke(style.stroke) / 2)
        case .arrow(let segment):
            return bounds(arrowOutline(segment, width: metrics.stroke(style.stroke)), outset: 0)
        case .pen(let points):
            return bounds(points, outset: metrics.stroke(style.stroke) / 2)
        case .highlighter(let points):
            return bounds(points, outset: metrics.highlighter(style.highlighter) / 2)
        case .mosaicStroke(let points):
            return bounds(points, outset: metrics.brush(style.brush) / 2)
        case .text(let text, let origin):
            return textFrame(text, origin: origin, style: style, metrics: metrics)
        case .step(let center):
            return stepCircle(at: center, style: style, metrics: metrics)
        }
    }

    static func selectionFrame(of annotation: Annotation, metrics: AnnotationMetrics) -> CGRect {
        frame(of: annotation, metrics: metrics).insetBy(dx: -metrics.selectionOutset, dy: -metrics.selectionOutset)
    }

    static func hits(_ annotation: Annotation, at point: CGPoint, metrics: AnnotationMetrics) -> Bool {
        let style = annotation.style
        let slop = metrics.hitSlop
        switch annotation.shape {
        case .rectangle(let rect):
            return nearEdge(of: rect, point, reach: metrics.stroke(style.stroke) / 2 + slop)
        case .mosaicBox(let rect):
            return nearEdge(of: rect, point, reach: slop)
        case .ellipse(let rect):
            return nearEllipse(rect, point, reach: metrics.stroke(style.stroke) / 2 + slop)
        case .line(let segment), .arrow(let segment):
            return distance(from: point, to: segment) <= metrics.stroke(style.stroke) * 1.5 + slop
        case .pen(let points):
            return distance(from: point, toPolyline: points) <= metrics.stroke(style.stroke) / 2 + slop
        case .highlighter(let points):
            return distance(from: point, toPolyline: points) <= metrics.highlighter(style.highlighter) / 2 + slop
        case .mosaicStroke:
            return false
        case .text(let text, let origin):
            return textFrame(text, origin: origin, style: style, metrics: metrics).insetBy(dx: -slop, dy: -slop)
                .contains(point)
        case .step(let center):
            let circle = stepCircle(at: center, style: style, metrics: metrics)
            return hypot(point.x - center.x, point.y - center.y) <= circle.width / 2 + slop
        }
    }

    static func distance(from point: CGPoint, to segment: Annotation.Segment) -> CGFloat {
        let dx = segment.end.x - segment.start.x
        let dy = segment.end.y - segment.start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - segment.start.x, point.y - segment.start.y) }
        let along = max(0, min(1, ((point.x - segment.start.x) * dx + (point.y - segment.start.y) * dy) / lengthSquared))
        return hypot(point.x - (segment.start.x + along * dx), point.y - (segment.start.y + along * dy))
    }

    private static func distance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return hypot(point.x - first.x, point.y - first.y) }
        return zip(points, points.dropFirst())
            .map { distance(from: point, to: Annotation.Segment(start: $0, end: $1)) }
            .min() ?? .infinity
    }

    private static func nearEdge(of rect: CGRect, _ point: CGPoint, reach: CGFloat) -> Bool {
        rect.insetBy(dx: -reach, dy: -reach).contains(point) && !rect.insetBy(dx: reach, dy: reach).contains(point)
    }

    private static func nearEllipse(_ rect: CGRect, _ point: CGPoint, reach: CGFloat) -> Bool {
        let a = rect.width / 2
        let b = rect.height / 2
        guard a > 0, b > 0 else { return nearEdge(of: rect, point, reach: reach) }
        let x = (point.x - rect.midX) / a
        let y = (point.y - rect.midY) / b
        return abs(hypot(x, y) - 1) * min(a, b) <= reach
    }

    private static func bounds(_ points: [CGPoint], outset: CGFloat) -> CGRect {
        guard let first = points.first else { return .null }
        let box = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        return box.insetBy(dx: -outset, dy: -outset)
    }

    private static func printable(_ text: String) -> String { text.isEmpty ? " " : text }
}
