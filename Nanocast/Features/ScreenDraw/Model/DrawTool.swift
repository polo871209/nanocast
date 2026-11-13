enum DrawTool: CaseIterable, Sendable {
    case rectangle, ellipse, arrow, line, pen, highlighter, text, eraser

    var key: Character {
        switch self {
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .arrow: return "a"
        case .line: return "l"
        case .pen: return "p"
        case .highlighter: return "h"
        case .text: return "t"
        case .eraser: return "e"
        }
    }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .text: return "Text"
        case .eraser: return "Eraser"
        }
    }

    var symbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .pen: return "scribble"
        case .highlighter: return "highlighter"
        case .text: return "character"
        case .eraser: return "eraser"
        }
    }

    /// The annotation the tool makes, or nil for the eraser, which removes marks instead.
    var markup: ScreenshotTool? {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .arrow: return .arrow
        case .line: return .line
        case .pen: return .pen
        case .highlighter: return .highlighter
        case .text: return .text
        case .eraser: return nil
        }
    }
}
