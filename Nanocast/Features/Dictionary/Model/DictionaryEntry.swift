import Foundation

struct DictionaryEntry: Equatable, Identifiable, Sendable {
    let term: String
    let blocks: [Block]

    var id: String { term }

    enum Block: Equatable, Sendable {
        case headword(String, homograph: String?, pronunciation: String?)
        case partOfSpeech([Run])
        case sense(number: String?, [Run])
        case subsense([Run])
        case note([Run])
        case section(String)
        case phrase([Run])
        case paragraph([Run])
    }

    struct Run: Equatable, Sendable {
        var text: String
        let style: Style
    }

    enum Style: Equatable, Sendable {
        case plain
        case example
        case label
        case strong
        case italic
    }

    var text: String {
        blocks.map(\.text).joined(separator: "\n")
    }
}

extension DictionaryEntry {
    init(term: String, plainText: String) {
        let pipes = plainText.ranges(of: "|").prefix(2)
        var pronunciation: String?
        var body = plainText[...]
        if pipes.count == 2 {
            let spoken = plainText[pipes[0].upperBound..<pipes[1].lowerBound]
                .trimmingCharacters(in: .whitespaces)
            pronunciation = spoken.isEmpty ? nil : spoken
            body = plainText[pipes[1].upperBound...]
        }
        let senses = body.split(separator: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Block.paragraph([Run(text: $0, style: .plain)]) }
        self.init(
            term: term,
            blocks: [.headword(term, homograph: nil, pronunciation: pronunciation)] + senses)
    }
}

extension DictionaryEntry.Block {
    var text: String {
        switch self {
        case .headword(let word, let homograph, let pronunciation):
            return [word, homograph, pronunciation.map { "| \($0) |" }]
                .compactMap { $0 }.joined(separator: " ")
        case .sense(let number, let runs):
            return [number, runs.text].compactMap { $0 }.joined(separator: " ")
        case .subsense(let runs): return "• " + runs.text
        case .section(let title): return "\n" + title
        case .partOfSpeech(let runs), .note(let runs), .phrase(let runs), .paragraph(let runs):
            return runs.text
        }
    }
}

extension [DictionaryEntry.Run] {
    var text: String { map(\.text).joined() }
}
