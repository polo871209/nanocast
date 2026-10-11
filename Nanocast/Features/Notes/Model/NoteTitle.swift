import Foundation

enum NoteTitle {
    static let untitled = "Untitled"

    static let headByteCount = 4096

    private static let scanLimit = 1024
    private static let displayLimit = 120

    static func isUnnamed(_ title: String) -> Bool {
        guard title.hasPrefix(untitled) else { return false }
        let suffix = title.dropFirst(untitled.count)
        guard !suffix.isEmpty else { return true }
        let digits = suffix.dropFirst()
        return suffix.hasPrefix(" ") && !digits.isEmpty
            && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    static func firstLine(of source: String) -> String? {
        let head = String(source.prefix(scanLimit))
        let text = head as NSString
        let markdown = NoteMarkdownParser.parse(head)
        for line in markdown.lines {
            let title = visibleText(of: line, in: markdown, text: text)
            guard !title.isEmpty else { continue }
            return String(title.prefix(displayLimit))
        }
        return nil
    }

    private static func visibleText(
        of line: NoteMarkdown.Line, in markdown: NoteMarkdown, text: NSString
    ) -> String {
        switch line.kind {
        case .blank, .rule, .fenceOpen, .fenceClose: return ""
        default: break
        }
        var visible = ""
        var cursor = line.contentRange.location
        let markers = markdown.inlines(of: line).flatMap(\.markerRanges)
        for marker in markers.sorted(by: { $0.location < $1.location }) {
            visible += text.substring(with: NSRange(cursor..<marker.location))
            cursor = NSMaxRange(marker)
        }
        visible += text.substring(with: NSRange(cursor..<NSMaxRange(line.contentRange)))
        return visible.trimmingCharacters(in: .whitespaces)
    }
}
