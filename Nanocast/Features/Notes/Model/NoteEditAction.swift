import Foundation

enum NoteEditAction: Sendable, Equatable {
    enum InlineStyle: Sendable, CaseIterable { case bold, italic, strikethrough, code }
    enum ListStyle: Sendable { case bullet, ordered, task }

    case newline
    case deleteBackward
    case indent
    case outdent
    case toggleInline(InlineStyle)
    case toggleLink
    case setHeading(level: Int)
    case toggleList(ListStyle)
    case toggleCodeBlock
    case toggleQuote
    case toggleTask(lineIndex: Int)
    case typedSpace
    case pasteURL(String)
}
