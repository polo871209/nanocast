import Foundation

enum ClipboardTextFileName {
    static func stem(for text: String) -> String {
        let firstLine =
            text.split(whereSeparator: \.isNewline)
            .first { !$0.allSatisfy(\.isWhitespace) } ?? ""
        let words = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let safe = String(words.map { "/:\\".contains($0) ? "-" : $0 })
        let visible = safe.drop(while: { $0 == "." || $0 == " " })
        let stem = String(visible.prefix(40)).trimmingCharacters(in: .whitespaces)
        return stem.isEmpty ? "Clipboard Text" : stem
    }
}
