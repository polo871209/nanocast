import CoreGraphics
import Foundation

struct AnnotationBoard: Sendable {
    private enum Drag {
        case create(ScreenshotTool, start: CGPoint, points: [CGPoint], style: AnnotationStyle, selectsMark: Bool)
        case move(ids: Set<Int>, from: CGPoint, before: [Annotation], click: Click?)
        case resize(handle: AnnotationGrip.Handle, from: CGPoint, original: Annotation, before: [Annotation])
        case moveEditing(from: CGPoint, origin: CGPoint)
        case erase(last: CGPoint, before: [Annotation])
        case marquee(from: CGPoint, to: CGPoint, kept: Set<Int>)
    }

    private enum Click {
        case openText(Int)
        case selectOnly(Int)
    }

    private struct Placed {
        let index: Int
        let annotation: Annotation
    }

    private(set) var annotations: [Annotation] = []
    private(set) var selectedIDs: Set<Int> = []
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
        case .create, .resize, .erase, .marquee, nil: return false
        }
    }

    var marquee: CGRect? {
        guard case .marquee(let from, let to, _) = drag else { return nil }
        return AnnotationGeometry.box(from: from, to: to)
    }

    var resizeDirection: SelectionHandle? {
        guard case .resize(let handle, _, let original, _) = drag,
            let current = annotations.first(where: { $0.id == original.id })
        else { return nil }
        return AnnotationGrip(current.shape)?.direction(of: handle)
    }

    var visible: [Annotation] {
        let all = annotations + [editing, draft].compactMap { $0 }
        return all.filter(\.isMosaic) + all.filter { !$0.isMosaic }
    }

    var selection: [Annotation] { annotations.filter { selectedIDs.contains($0.id) } }

    /// The one selected mark, or nil when none or several are selected.
    var selected: Annotation? { selectedIDs.count == 1 ? selection.first : nil }

    func selectionBounds(metrics: AnnotationMetrics) -> CGRect? {
        let frames = selection.map { AnnotationGeometry.selectionFrame(of: $0, metrics: metrics) }
        return frames.dropFirst().reduce(frames.first) { $0?.union($1) }
    }

    func annotation(at point: CGPoint, metrics: AnnotationMetrics) -> Annotation? {
        let marks = annotations.filter { !$0.isMosaic }
        let mosaic = annotations.filter(\.isMosaic)
        return (marks.reversed() + mosaic.reversed()).first {
            AnnotationGeometry.hits($0, at: point, metrics: metrics)
        }
    }

    func resizeDirection(at point: CGPoint, metrics: AnnotationMetrics) -> SelectionHandle? {
        guard let selected, let grip = AnnotationGrip(selected.shape),
            let handle = grip.handle(at: point, reach: metrics.handleReach)
        else { return nil }
        return grip.direction(of: handle)
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
        draft = nil
        if let selected, let handle = AnnotationGrip(selected.shape)?.handle(at: point, reach: metrics.handleReach) {
            drag = .resize(handle: handle, from: point, original: selected, before: annotations)
            return false
        }
        selectedIDs = []
        if let hit = annotation(at: point, metrics: metrics) {
            selectedIDs = [hit.id]
            drag = .move(
                ids: [hit.id], from: point, before: annotations,
                click: tool == .text && hit.isTyped ? .openText(hit.id) : nil)
            return false
        }
        if tool == .text {
            editing = Annotation(id: makeID(), shape: .text("", origin: point), style: style)
            editingOriginal = nil
            return true
        }
        drag = .create(tool, start: point, points: [point], style: style, selectsMark: true)
        if tool == .step { draft = Annotation(id: makeID(), shape: .step(center: point), style: style) }
        return false
    }

    /// Starts a new mark at `point`, even over an existing one, for a live drawing.
    mutating func beginStroke(at point: CGPoint, tool: ScreenshotTool, style: AnnotationStyle) {
        draft = nil
        selectedIDs = []
        drag = .create(tool, start: point, points: [point], style: style, selectsMark: false)
    }

    /// Picks marks for a select tool. A press on a mark or inside the selection moves the selection, and a
    /// press elsewhere drags a selection box. With `adding`, the press toggles the mark under it, or the box
    /// adds its marks, and the rest of the selection stays.
    mutating func beginSelecting(at point: CGPoint, adding: Bool, metrics: AnnotationMetrics) {
        draft = nil
        let hit = annotation(at: point, metrics: metrics)
        if adding, let hit, selectedIDs.contains(hit.id) {
            selectedIDs.remove(hit.id)
            drag = nil
            return
        }
        let grabsSelection = !adding && selectionBounds(metrics: metrics)?.contains(point) == true
        guard let hit else {
            if grabsSelection {
                drag = .move(ids: selectedIDs, from: point, before: annotations, click: nil)
            } else {
                if !adding { selectedIDs = [] }
                drag = .marquee(from: point, to: point, kept: selectedIDs)
            }
            return
        }
        if adding {
            selectedIDs.insert(hit.id)
        } else if !selectedIDs.contains(hit.id) {
            selectedIDs = [hit.id]
        }
        drag = .move(ids: selectedIDs, from: point, before: annotations, click: adding ? nil : .selectOnly(hit.id))
    }

    mutating func selectAll() {
        selectedIDs = Set(annotations.map(\.id))
    }

    /// Opens a new empty text at `point` for typing, even over an existing mark.
    mutating func beginText(at point: CGPoint, style: AnnotationStyle) {
        draft = nil
        selectedIDs = []
        drag = nil
        editing = Annotation(id: makeID(), shape: .text("", origin: point), style: style)
        editingOriginal = nil
    }

    /// Removes every mark the drag passes over, as one undo step.
    mutating func beginErasing(at point: CGPoint, metrics: AnnotationMetrics) {
        draft = nil
        selectedIDs = []
        drag = .erase(last: point, before: annotations)
        erase(along: Annotation.Segment(start: point, end: point), metrics: metrics)
    }

    mutating func clear() {
        guard !annotations.isEmpty else { return }
        history.record(annotations)
        annotations.removeAll()
        selectedIDs = []
    }

    mutating func drag(to point: CGPoint, constrained: Bool, metrics: AnnotationMetrics) {
        switch drag {
        case .erase(let last, let before):
            erase(along: Annotation.Segment(start: last, end: point), metrics: metrics)
            drag = .erase(last: point, before: before)
        case .move(let ids, let from, let before, _):
            let offset = CGVector(dx: point.x - from.x, dy: point.y - from.y)
            guard annotations != before || hypot(offset.dx, offset.dy) > metrics.dragSlop else { return }
            annotations = before.map { ids.contains($0.id) ? $0.moved(by: offset) : $0 }
        case .marquee(let from, _, let kept):
            drag = .marquee(from: from, to: point, kept: kept)
            let box = AnnotationGeometry.box(from: from, to: point)
            let boxed = annotations.filter { box.contains(AnnotationGeometry.frame(of: $0, metrics: metrics)) }
            selectedIDs = kept.union(boxed.map(\.id))
        case .resize(let handle, let from, let original, _):
            guard let index = annotations.firstIndex(where: { $0.id == original.id }),
                let grip = AnnotationGrip(original.shape)
            else { return }
            let offset = CGVector(dx: point.x - from.x, dy: point.y - from.y)
            annotations[index].shape = grip.dragging(handle, by: offset, constrained: constrained)
                .reshaping(original.shape)
        case .moveEditing(let from, let origin):
            guard var editing, case .text(let text, _) = editing.shape else { return }
            editing.shape = .text(text, origin: CGPoint(x: origin.x + point.x - from.x, y: origin.y + point.y - from.y))
            self.editing = editing
        case .create(let tool, let start, var points, let style, let selectsMark):
            if points.last != point { points.append(point) }
            drag = .create(tool, start: start, points: points, style: style, selectsMark: selectsMark)
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
        case .move(_, _, let before, let click):
            if annotations != before {
                history.record(before)
                return
            }
            switch click {
            case .openText(let id)?:
                selectedIDs = []
                beginEditing(id)
            case .selectOnly(let id)?:
                selectedIDs = [id]
            case nil:
                return
            }
        case .resize(_, _, let original, let before):
            guard let index = annotations.firstIndex(where: { $0.id == original.id }), annotations[index] != original
            else { return }
            if Self.hasExtent(annotations[index].shape) {
                history.record(before)
            } else {
                annotations[index] = original
            }
        case .moveEditing, .marquee:
            return
        case .erase(_, let before):
            if annotations != before { history.record(before) }
        case .create(_, _, _, _, let selectsMark):
            defer { self.draft = nil }
            guard let draft, Self.hasExtent(draft.shape) else { return }
            history.record(annotations)
            annotations.append(draft)
            if selectsMark, AnnotationGrip(draft.shape) != nil { selectedIDs = [draft.id] }
        case nil:
            return
        }
    }

    mutating func editText(at point: CGPoint, metrics: AnnotationMetrics) -> Bool {
        guard let hit = annotation(at: point, metrics: metrics), hit.isTyped else { return false }
        drag = nil
        selectedIDs = []
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
        selectedIDs = id.map { [$0] } ?? []
    }

    mutating func deleteSelected() {
        guard !selection.isEmpty else { return }
        history.record(annotations)
        annotations.removeAll { selectedIDs.contains($0.id) }
        selectedIDs = []
    }

    mutating func restyleSelected(_ style: AnnotationStyle) {
        guard selection.contains(where: { $0.style != style }) else { return }
        history.record(annotations)
        for index in annotations.indices where selectedIDs.contains(annotations[index].id) {
            annotations[index].style = style
        }
    }

    mutating func undo() {
        guard let previous = history.undo(from: annotations) else { return }
        annotations = previous
        selectedIDs = []
    }

    mutating func redo() {
        guard let next = history.redo(from: annotations) else { return }
        annotations = next
        selectedIDs = []
    }

    private mutating func erase(along segment: Annotation.Segment, metrics: AnnotationMetrics) {
        let samples = Int((segment.length / max(metrics.hitSlop, 1)).rounded(.up))
        let points = (0...samples).map { index in
            let t = samples == 0 ? 0 : CGFloat(index) / CGFloat(samples)
            return CGPoint(
                x: segment.start.x + (segment.end.x - segment.start.x) * t,
                y: segment.start.y + (segment.end.y - segment.start.y) * t)
        }
        annotations.removeAll { mark in points.contains { AnnotationGeometry.hits(mark, at: $0, metrics: metrics) } }
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
        let box = AnnotationGeometry.box(
            from: start, to: constrained ? AnnotationGeometry.square(from: start, to: end) : end)
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
