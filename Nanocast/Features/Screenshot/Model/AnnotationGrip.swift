import CoreGraphics

enum AnnotationGrip: Equatable, Sendable {
    enum Handle: Equatable, Sendable {
        case box(SelectionHandle)
        case start
        case end
    }

    case box(CGRect)
    case segment(Annotation.Segment)

    init?(_ shape: Annotation.Shape) {
        switch shape {
        case .rectangle(let rect), .ellipse(let rect), .mosaicBox(let rect):
            self = .box(rect)
        case .line(let segment), .arrow(let segment):
            self = .segment(segment)
        case .highlighter(let points) where points.count == 2:
            self = .segment(Annotation.Segment(start: points[0], end: points[1]))
        case .highlighter, .pen, .text, .step, .mosaicStroke:
            return nil
        }
    }

    var handles: [(handle: Handle, point: CGPoint)] {
        switch self {
        case .box(let rect): return SelectionHandle.allCases.map { (.box($0), $0.point(on: rect)) }
        case .segment(let segment): return [(.start, segment.start), (.end, segment.end)]
        }
    }

    func handle(at point: CGPoint, reach: CGFloat) -> Handle? {
        handles
            .map { (handle: $0.handle, distance: hypot($0.point.x - point.x, $0.point.y - point.y)) }
            .filter { $0.distance <= reach }
            .min { $0.distance < $1.distance }?.handle
    }

    func direction(of handle: Handle) -> SelectionHandle? {
        switch (self, handle) {
        case (_, .box(let handle)):
            return handle
        case (.segment(let segment), .start):
            return SelectionHandle(pointing: CGVector(dx: segment.start.x - segment.end.x, dy: segment.start.y - segment.end.y))
        case (.segment(let segment), .end):
            return SelectionHandle(pointing: CGVector(dx: segment.end.x - segment.start.x, dy: segment.end.y - segment.start.y))
        case (.box, .start), (.box, .end):
            return nil
        }
    }

    func dragging(_ handle: Handle, by offset: CGVector, constrained: Bool) -> AnnotationGrip {
        func shifted(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + offset.dx, y: point.y + offset.dy) }
        switch (self, handle) {
        case (.box(let rect), .box(let handle)):
            let fixed = handle.opposite.point(on: rect)
            let pointer = shifted(handle.point(on: rect))
            switch handle {
            case .left, .right:
                return .box(
                    AnnotationGeometry.box(
                        from: CGPoint(x: fixed.x, y: rect.minY), to: CGPoint(x: pointer.x, y: rect.maxY)))
            case .top, .bottom:
                return .box(
                    AnnotationGeometry.box(
                        from: CGPoint(x: rect.minX, y: fixed.y), to: CGPoint(x: rect.maxX, y: pointer.y)))
            case .topLeft, .topRight, .bottomRight, .bottomLeft:
                let corner = constrained ? AnnotationGeometry.square(from: fixed, to: pointer) : pointer
                return .box(AnnotationGeometry.box(from: fixed, to: corner))
            }
        case (.segment(var segment), .start):
            let pointer = shifted(segment.start)
            segment.start = constrained ? AnnotationGeometry.snapped(from: segment.end, to: pointer) : pointer
            return .segment(segment)
        case (.segment(var segment), .end):
            let pointer = shifted(segment.end)
            segment.end = constrained ? AnnotationGeometry.snapped(from: segment.start, to: pointer) : pointer
            return .segment(segment)
        case (.box, .start), (.box, .end), (.segment, .box):
            return self
        }
    }

    func reshaping(_ shape: Annotation.Shape) -> Annotation.Shape {
        switch (shape, self) {
        case (.rectangle, .box(let rect)): return .rectangle(rect)
        case (.ellipse, .box(let rect)): return .ellipse(rect)
        case (.mosaicBox, .box(let rect)): return .mosaicBox(rect)
        case (.line, .segment(let segment)): return .line(segment)
        case (.arrow, .segment(let segment)): return .arrow(segment)
        case (.highlighter, .segment(let segment)): return .highlighter([segment.start, segment.end])
        default: return shape
        }
    }
}
