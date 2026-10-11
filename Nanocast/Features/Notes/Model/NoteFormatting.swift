import Foundation

struct NoteFormatting: Sendable, Equatable {
    var headingLevel: Int?
    var inlineStyles: Set<NoteEditAction.InlineStyle>
    var isLink: Bool
    var isCodeBlock: Bool
    var isQuote: Bool
    var list: NoteEditAction.ListStyle?

    static let plain = NoteFormatting(
        headingLevel: nil, inlineStyles: [], isLink: false, isCodeBlock: false, isQuote: false, list: nil)
}
