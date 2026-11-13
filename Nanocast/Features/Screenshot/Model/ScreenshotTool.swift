enum ScreenshotTool: CaseIterable, Sendable {
    case rectangle, ellipse, line, arrow, pen, highlighter, text, step, mosaic

    init?(key: Character) {
        guard let tool = Self.allCases.first(where: { $0.key == key }) else { return nil }
        self = tool
    }

    var key: Character {
        switch self {
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .line: return "l"
        case .arrow: return "a"
        case .pen: return "p"
        case .highlighter: return "h"
        case .text: return "t"
        case .step: return "n"
        case .mosaic: return "b"
        }
    }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .text: return "Text"
        case .step: return "Step"
        case .mosaic: return "Mosaic"
        }
    }

    var symbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .pen: return "scribble"
        case .highlighter: return "highlighter"
        case .text: return "character"
        case .step: return "1.circle"
        case .mosaic: return "ScreenshotMosaic"
        }
    }

    var startsGroup: Bool { self == .mosaic }
}
