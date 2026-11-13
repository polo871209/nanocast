import CoreGraphics

struct Annotation: Identifiable, Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        var start: CGPoint
        var end: CGPoint

        var length: CGFloat { hypot(end.x - start.x, end.y - start.y) }
    }

    enum Shape: Equatable, Sendable {
        case rectangle(CGRect)
        case ellipse(CGRect)
        case line(Segment)
        case arrow(Segment)
        case pen([CGPoint])
        case highlighter([CGPoint])
        case text(String, origin: CGPoint)
        case step(center: CGPoint)
        case mosaicBox(CGRect)
        case mosaicStroke([CGPoint])
    }

    let id: Int
    var shape: Shape
    var style: AnnotationStyle

    var typedText: String? {
        guard case .text(let text, _) = shape else { return nil }
        return text
    }

    var isTyped: Bool { typedText != nil }

    var isMosaic: Bool {
        switch shape {
        case .mosaicBox, .mosaicStroke: return true
        default: return false
        }
    }

    func moved(by offset: CGVector) -> Annotation {
        func shift(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + offset.dx, y: point.y + offset.dy) }
        func shift(_ segment: Segment) -> Segment { Segment(start: shift(segment.start), end: shift(segment.end)) }
        var moved = self
        switch shape {
        case .rectangle(let rect): moved.shape = .rectangle(rect.offsetBy(dx: offset.dx, dy: offset.dy))
        case .ellipse(let rect): moved.shape = .ellipse(rect.offsetBy(dx: offset.dx, dy: offset.dy))
        case .line(let segment): moved.shape = .line(shift(segment))
        case .arrow(let segment): moved.shape = .arrow(shift(segment))
        case .pen(let points): moved.shape = .pen(points.map(shift))
        case .highlighter(let points): moved.shape = .highlighter(points.map(shift))
        case .text(let string, let origin): moved.shape = .text(string, origin: shift(origin))
        case .step(let center): moved.shape = .step(center: shift(center))
        case .mosaicBox(let rect): moved.shape = .mosaicBox(rect.offsetBy(dx: offset.dx, dy: offset.dy))
        case .mosaicStroke(let points): moved.shape = .mosaicStroke(points.map(shift))
        }
        return moved
    }
}
