import Foundation

enum FuzzyMatch {
    enum Tier: Sendable {
        case exact
        case prefix
        case wordStart
        case substring
        case subsequence
    }

    struct Match: Sendable {
        let tier: Tier
        let offset: Int
        let queryLength: Int
        let candidateLength: Int
        let spread: Int

        var score: Int { FuzzyMatch.rawScore(self) }
    }

    struct Query: Sendable {
        fileprivate let text: String
        fileprivate let characters: [Character]
        var isEmpty: Bool { text.isEmpty }

        init(_ raw: String) {
            text = FuzzyMatch.normalized(raw)
            characters = Array(text)
        }
    }

    struct Candidate: Sendable {
        let text: String
        fileprivate let length: Int

        init(_ raw: String) {
            text = FuzzyMatch.normalized(raw)
            length = text.count
        }
    }

    static func match(query: String, candidate: String) -> Match? {
        match(Query(query), candidate: candidate)
    }

    static func match(_ query: Query, candidate: String) -> Match? {
        match(query, candidate: Candidate(candidate))
    }

    static func match(_ query: Query, candidate: Candidate) -> Match? {
        let q = query.text
        let c = candidate.text
        let length = candidate.length
        guard !q.isEmpty else {
            return Match(
                tier: .exact, offset: 0, queryLength: 0, candidateLength: length, spread: 0)
        }

        if c == q {
            return Match(
                tier: .exact, offset: 0, queryLength: query.characters.count,
                candidateLength: length, spread: 0)
        }
        if c.hasPrefix(q) {
            return Match(
                tier: .prefix, offset: 0, queryLength: query.characters.count,
                candidateLength: length, spread: 0)
        }
        if let range = c.range(of: q) {
            let offset = c.distance(from: c.startIndex, to: range.lowerBound)
            return Match(
                tier: isWordStart(c, range.lowerBound) ? .wordStart : .substring, offset: offset,
                queryLength: query.characters.count, candidateLength: length, spread: 0)
        }
        guard let spread = subsequenceScore(query.characters, c) else { return nil }
        return Match(
            tier: .subsequence, offset: 0, queryLength: query.characters.count,
            candidateLength: length, spread: spread)
    }

    static func score(_ query: Query, candidate: String) -> Int? {
        match(query, candidate: candidate).map(rawScore)
    }

    static func score(_ query: Query, candidate: Candidate) -> Int? {
        match(query, candidate: candidate).map(rawScore)
    }

    fileprivate static func rawScore(_ match: Match) -> Int {
        switch match.tier {
        case .exact: 100_000
        case .prefix: 90_000 - match.candidateLength
        case .wordStart: 80_000 - match.candidateLength
        case .substring: 70_000 - match.candidateLength
        case .subsequence: match.spread
        }
    }

    static func normalized(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0.value >= 0xAD }) else {
            return value.lowercased()
        }
        // Composed first, so a Korean or Vietnamese IME's decomposed input folds like typed text.
        let composed = value.precomposedStringWithCanonicalMapping
        let scalars = composed.unicodeScalars.filter { $0.properties.generalCategory != .format }
        return String(String.UnicodeScalarView(scalars)).folding(options: folding, locale: nil)
    }

    /// Locale-independent: a Turkish fold maps "I" to "ı" and orphans every stored key.
    static let folding: String.CompareOptions = [
        .caseInsensitive, .diacriticInsensitive, .widthInsensitive
    ]

    private static func isWordStart(_ s: String, _ index: String.Index) -> Bool {
        if index == s.startIndex { return true }
        let before = s[s.index(before: index)]
        return !before.isLetter && !before.isNumber
    }

    private static func subsequenceScore(_ q: [Character], _ c: String) -> Int? {
        var qi = 0
        var score = 0
        var run = 0
        var prev = -2
        var ci = 0
        var previous: Character?
        for ch in c {
            if qi < q.count, ch == q[qi] {
                var bonus = 1
                if ci == prev + 1 {
                    run += 1
                    bonus += run * 3
                } else {
                    run = 0
                }
                if ci == 0 {
                    bonus += 12
                } else if let previous, !previous.isLetter, !previous.isNumber {
                    bonus += 8
                }
                score += bonus
                prev = ci
                qi += 1
                if qi == q.count { break }
            }
            previous = ch
            ci += 1
        }
        guard qi == q.count else { return nil }
        return score
    }

    static func referenceSpread(_ queryLength: Int) -> Int {
        guard queryLength > 0 else { return 1 }
        return 13 + (queryLength - 1) + 3 * queryLength * (queryLength - 1) / 2
    }
}

struct SearchAlias: Sendable, Hashable {
    enum Role: Sendable {
        case owner
        case name
    }

    let text: String
    let role: Role

    init(_ text: String, _ role: Role) {
        self.text = text
        self.role = role
    }

    static func name(_ text: String) -> Self { Self(text, .name) }
    static func owner(_ text: String) -> Self { Self(text, .owner) }
}

struct SearchFields: Sendable, Hashable, ExpressibleByArrayLiteral {
    var aliases: [SearchAlias]

    init(_ aliases: [SearchAlias] = []) { self.aliases = aliases }
    init(arrayLiteral elements: SearchAlias...) { aliases = elements }
}

enum SearchRelevance {
    static let shapeSpan = 99

    static func cell(_ role: SearchAlias.Role, _ tier: FuzzyMatch.Tier) -> Int? {
        switch (role, tier) {
        case (.name, .exact): 6_500
        case (.name, .prefix): 3_000
        case (.owner, .exact): 2_500
        case (.name, .wordStart): 2_400
        case (.owner, .prefix): 2_000
        case (.name, .substring): 1_800
        case (.owner, .wordStart): 1_500
        case (.owner, .substring): 1_100
        case (.name, .subsequence): 1_000
        case (.owner, .subsequence): nil
        }
    }

    static func shape(_ match: FuzzyMatch.Match) -> Int {
        guard match.candidateLength > 0 else { return 0 }
        let coverage = min(1, Double(match.queryLength) / Double(match.candidateLength))
        let positional =
            match.tier == .subsequence
            ? min(1, Double(match.spread) / Double(FuzzyMatch.referenceSpread(match.queryLength)))
            : 1 / (1 + Double(match.offset) / 4)
        return Int((Double(shapeSpan) * (0.6 * coverage + 0.4 * positional)).rounded())
    }

    static func quality(query: String, fields: SearchFields) -> Int? {
        quality(FuzzyMatch.Query(query), fields: fields)
    }

    static func quality(_ query: FuzzyMatch.Query, fields: SearchFields) -> Int? {
        guard !query.isEmpty else { return 0 }
        var best: Int?
        for alias in fields.aliases {
            guard let match = FuzzyMatch.match(query, candidate: alias.text),
                let cell = cell(alias.role, match.tier)
            else { continue }
            best = max(best ?? Int.min, cell + shape(match))
        }
        return best
    }
}
