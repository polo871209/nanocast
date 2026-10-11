import AppKit

@MainActor
enum NoteMarkdownTypography {
    static let body = NSFont.systemFont(ofSize: size(.title3))
    static let heading1 = NSFont.systemFont(ofSize: size(.largeTitle), weight: .bold)
    static let heading2 = NSFont.systemFont(ofSize: size(.title1), weight: .bold)
    static let heading3 = NSFont.systemFont(ofSize: size(.title2), weight: .semibold)
    static let inlineCode = NSFont.monospacedSystemFont(ofSize: body.pointSize, weight: .regular)
    static let codeBlock = NSFont.monospacedSystemFont(ofSize: body.pointSize - 1, weight: .regular)
    static let hidden = NSFont.systemFont(ofSize: 0.01)

    static func heading(_ level: Int) -> NSFont {
        switch level {
        case 1: heading1
        case 2: heading2
        default: heading3
        }
    }

    static func adding(_ traits: NSFontDescriptor.SymbolicTraits, to font: NSFont) -> NSFont {
        let current = font.fontDescriptor.symbolicTraits
        let descriptor = font.fontDescriptor.withSymbolicTraits(current.union(traits))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    private static func size(_ style: NSFont.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: style).pointSize
    }

    static func inlineCode(matching font: NSFont) -> NSFont {
        font.pointSize == body.pointSize
            ? inlineCode : NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
    }
}
