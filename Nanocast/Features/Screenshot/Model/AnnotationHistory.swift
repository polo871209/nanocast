struct AnnotationHistory: Sendable {
    private var past: [[Annotation]] = []
    private var future: [[Annotation]] = []

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    mutating func record(_ before: [Annotation]) {
        past.append(before)
        future.removeAll()
    }

    mutating func undo(from current: [Annotation]) -> [Annotation]? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    mutating func redo(from current: [Annotation]) -> [Annotation]? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }
}
