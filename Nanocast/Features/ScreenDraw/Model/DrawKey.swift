enum DrawKey: Equatable, Sendable {
    case tool(DrawTool)
    case ink(AnnotationStyle.Ink)

    init?(_ character: Character) {
        if let tool = DrawTool.allCases.first(where: { $0.key == character }) {
            self = .tool(tool)
        } else if let ink = AnnotationStyle.Ink.allCases.first(where: { Self.digit(for: $0) == character }) {
            self = .ink(ink)
        } else {
            return nil
        }
    }

    static func digit(for ink: AnnotationStyle.Ink) -> Character {
        let index = AnnotationStyle.Ink.allCases.firstIndex(of: ink) ?? 0
        return Character(String(index + 1))
    }
}
