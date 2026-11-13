/// A description
enum DrawTool: CaseIterable, Sendable {
    case pen, highlighter, rectangle, ellipse, eraser

    var key: Character {
        switch self {
        case .pen: return "p"
        case .highlighter: return "h"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .eraser: return "e"
        }
    }

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .eraser: return "Eraser"
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "scribble"
        case .highlighter: return "highlighter"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .eraser: return "eraser"
        }
    }

    /// The annotation a drag draws, or nil for the eraser, which removes marks instead.
    var markup: ScreenshotTool? {
        switch self {
        case .pen: return .pen
        case .highlighter: return .highlighter
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .eraser: return nil
        }
    }
}
