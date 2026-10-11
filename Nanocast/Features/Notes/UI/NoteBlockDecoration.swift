import AppKit

extension NSAttributedString.Key {
    static let noteBlockDecoration = NSAttributedString.Key("nanocast.note.blockDecoration")
}

final class NoteBlockDecoration: NSObject, Sendable {
    enum Shape: Sendable, Equatable, Hashable {
        enum CodeRow: Sendable, Hashable { case top, middle, bottom, single }
        case code(CodeRow, language: String?)
        case quote(depth: Int)
        case rule
        case bullet(level: Int)
        case ordered(level: Int, label: String)
        case task(level: Int, checked: Bool)
    }

    let shape: Shape
    let fill: NSColor
    let ink: NSColor
    let bodyPointSize: CGFloat

    init(shape: Shape, fill: NSColor, ink: NSColor, bodyPointSize: CGFloat) {
        self.shape = shape
        self.fill = fill
        self.ink = ink
        self.bodyPointSize = bodyPointSize
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NoteBlockDecoration else { return false }
        return shape == other.shape && fill == other.fill && ink == other.ink
            && bodyPointSize == other.bodyPointSize
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(shape)
        hasher.combine(fill)
        hasher.combine(ink)
        hasher.combine(bodyPointSize)
        return hasher.finalize()
    }
}
