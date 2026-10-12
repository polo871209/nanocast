import CoreGraphics
import Foundation

struct AnnotationBoard: Sendable {
    private enum Drag {
        case create(ScreenshotTool, start: CGPoint, points: [CGPoint], style: AnnotationStyle)
        case move(id: Int, from: CGPoint, original: Annotation, before: [Annotation], opensTextOnClick: Bool)
        case moveEditing(from: CGPoint, origin: CGPoint)
    }

    private struct Placed {
        let index: Int
        let annotation: Annotation
    }

    private(set) var annotations: [Annotation] = []
    private(set) var selectedID: Int?
    private(set) var draft: Annotation?
    private(set) var editing: Annotation?
    private var editingOriginal: Placed?
    private var drag: Drag?
    private var history = AnnotationHistory()
    private var nextID = 1

    var isEmpty: Bool { annotations.isEmpty && draft == nil && editing == nil }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var isMoving: Bool {
        switch drag {
        case .move, .moveEditing: return true
        case .create, nil: return false
        }
    }

    var visible: [Annotation] {
        let all = annotations + [editing, draft].compactMap { $0 }
        return all.filter(\.isMosaic) + all.filter { !$0.isMosaic }
    }

    var selected: Annotation? { annotations.first { $0.id == selectedID } }

    func annotation(at point: CGPoint, metrics: AnnotationMetrics) -> Annotation? {
        let marks = annotations.filter { !$0.isMosaic }
        let mosaic = annotations.filter(\.isMosaic)
        return (marks.reversed() + mosaic.reversed()).first {
            AnnotationGeometry.hits($0, at: point, metrics: metrics)
        }
    }

    func gripsEditing(at point: CGPoint, metrics: AnnotationMetrics) -> Bool {
        guard let editing else { return false }
        let box = AnnotationGeometry.selectionFrame(of: editing, metrics: metrics)
        let text = AnnotationGeometry.frame(of: editing, metrics: metrics)
        return box.insetBy(dx: -metrics.hitSlop, dy: -metrics.hitSlop).contains(point) && !text.contains(point)
    }

    mutating func grabEditing(at point: CGPoint, metrics: AnnotationMetrics) -> Bool {
        guard gripsEditing(at: point, metrics: metrics), case .text(_, let origin)? = editing?.shape else { return false }
        drag = .moveEditing(from: point, origin: origin)
        return true
    }

    mutating func press(
        at point: CGPoint, tool: ScreenshotTool, style: AnnotationStyle, metrics: AnnotationMetrics
    ) -> Bool {
        selectedID = nil
        draft = nil
        if let hit = annotation(at: point, metrics: metrics) {
            selectedID = hit.id
            drag = .move(
                id: hit.id, from: point, original: hit, before: annotations, opensTextOnClick: tool == .text && hit.isTyped)
            return false
        }
        if tool == .text {
            editing = Annotation(id: makeID(), shape: .text("", origin: point), style: style)
            editingOriginal = nil
            return true
        }
        drag = .create(tool, start: point, points: [point], style: style)
        if tool == .step { draft = Annotation(id: makeID(), shape: .step(center: point), style: style) }
        return false
    }

    mutating func drag(to point: CGPoint, constrained: Bool, metrics: AnnotationMetrics) {
        switch drag {
        case .move(let id, let from, let original, _, _):
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
            let offset = CGVector(dx: point.x - from.x, dy: point.y - from.y)
            let started = annotations[index] != original
            guard started || hypot(offset.dx, offset.dy) > metrics.dragSlop else { return }
            annotations[index] = original.moved(by: offset)
        case .moveEditing(let from, let origin):
            guard var editing, case .text(let text, _) = editing.shape else { return }
            editing.shape = .text(text, origin: CGPoint(x: origin.x + point.x - from.x, y: origin.y + point.y - from.y))
            self.editing = editing
        case .create(let tool, let start, var points, let style):
            if points.last != point { points.append(point) }
            drag = .create(tool, start: start, points: points, style: style)
            guard draft != nil || hypot(point.x - start.x, point.y - start.y) > metrics.dragSlop,
                let shape = Self.shape(tool, start: start, end: point, points: points, style: style, constrained: constrained)
            else { return }
            draft = Annotation(id: draft?.id ?? makeID(), shape: shape, style: style)
        case nil:
            return
        }
    }

    mutating func release() {
        defer { drag = nil }
        switch drag {
        case .move(let id, _, let original, let before, let opensTextOnClick):
            if annotations.first(where: { $0.id == id }) != original {
                history.record(before)
            } else if opensTextOnClick {
                selectedID = nil
                beginEditing(id)
            }
        case .moveEditing:
            return
        case .create:
            defer { self.draft = nil }
            guard let draft, Self.hasExtent(draft.shape) else { return }
            history.record(annotations)
            annotations.append(draft)
        case nil:
            return
        }
    }

    mutating func editText(at point: CGPoint, metrics: AnnotationMetrics) -> Bool {
        guard let hit = annotation(at: point, metrics: metrics), hit.isTyped else { return false }
        drag = nil
        selectedID = nil
        beginEditing(hit.id)
        return true
    }

    mutating func restyleEditing(_ style: AnnotationStyle) {
        editing?.style = style
    }

    mutating func updateEditing(_ text: String) {
        guard var editing, case .text(_, let origin) = editing.shape else { return }
        editing.shape = .text(text, origin: origin)
        self.editing = editing
    }

    mutating func endEditing() {
        guard let editing else { return }
        let original = editingOriginal
        self.editing = nil
        editingOriginal = nil
        var before = annotations
        if let original { before.insert(original.annotation, at: min(original.index, before.count)) }
        let text = editing.typedText ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if original != nil { history.record(before) }
            return
        }
        guard let original else {
            history.record(before)
            annotations.append(editing)
            return
        }
        if original.annotation != editing { history.record(before) }
        annotations.insert(editing, at: min(original.index, annotations.count))
    }

    mutating func add(_ shape: Annotation.Shape, style: AnnotationStyle) {
        history.record(annotations)
        annotations.append(Annotation(id: makeID(), shape: shape, style: style))
    }

    mutating func select(_ id: Int?) {
        selectedID = id
    }

    mutating func deleteSelected() {
        guard let selectedID, annotations.contains(where: { $0.id == selectedID }) else { return }
        history.record(annotations)
        annotations.removeAll { $0.id == selectedID }
        self.selectedID = nil
    }

    mutating func restyleSelected(_ style: AnnotationStyle) {
        guard let index = annotations.firstIndex(where: { $0.id == selectedID }), annotations[index].style != style
        else { return }
        history.record(annotations)
        annotations[index].style = style
    }

    mutating func undo() {
        guard let previous = history.undo(from: annotations) else { return }
        annotations = previous
        selectedID = nil
    }

    mutating func redo() {
        guard let next = history.redo(from: annotations) else { return }
        annotations = next
        selectedID = nil
    }

    private mutating func beginEditing(_ id: Int) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        editingOriginal = Placed(index: index, annotation: annotations[index])
        editing = annotations.remove(at: index)
    }

    private mutating func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private static func hasExtent(_ shape: Annotation.Shape) -> Bool {
        switch shape {
        case .rectangle(let rect), .ellipse(let rect), .mosaicBox(let rect):
            return !rect.isEmpty
        case .line(let segment), .arrow(let segment):
            return segment.length > 0
        case .pen(let points), .highlighter(let points), .mosaicStroke(let points):
            return points.contains { $0 != points.first }
        case .text, .step:
            return true
        }
    }

    private static func shape(
        _ tool: ScreenshotTool, start: CGPoint, end: CGPoint, points: [CGPoint], style: AnnotationStyle,
        constrained: Bool
    ) -> Annotation.Shape? {
        let corner = constrained ? AnnotationGeometry.square(from: start, to: end) : end
        let box = CGRect(
            x: min(start.x, corner.x), y: min(start.y, corner.y), width: abs(corner.x - start.x),
            height: abs(corner.y - start.y))
        let segment = Annotation.Segment(
            start: start, end: constrained ? AnnotationGeometry.snapped(from: start, to: end) : end)
        switch tool {
        case .rectangle: return .rectangle(box)
        case .ellipse: return .ellipse(box)
        case .line: return .line(segment)
        case .arrow: return .arrow(segment)
        case .pen: return .pen(points)
        case .highlighter: return .highlighter(style.highlighterFreehand ? points : [start, segment.end])
        case .step: return .step(center: end)
        case .mosaic: return style.mosaicBrush ? .mosaicStroke(points) : .mosaicBox(box)
        case .text: return nil
        }
    }
}
