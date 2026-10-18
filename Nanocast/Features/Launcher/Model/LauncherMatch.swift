import Foundation

struct SearchText: Sendable, Hashable {
    let units: [UInt16]
    let humps: [Int]

    var isEmpty: Bool { units.isEmpty }
    var string: String { String(decoding: units, as: UTF16.self) }

    init(_ raw: String, transliterated: Bool) {
        let latin = transliterated ? ScriptRomanization.latin(raw) : nil
        units = Array((latin ?? FuzzyMatch.normalized(raw)).utf16)
        humps = latin == nil ? Self.humps(in: raw) : []
    }

    init(units: [UInt16], humps: [Int] = []) {
        self.units = units
        self.humps = humps
    }

    func joined(with other: SearchText) -> SearchText {
        SearchText(
            units: units + [LauncherMatch.space] + other.units,
            humps: humps + other.humps.map { $0 + units.count + 1 })
    }

    private static let lowercase = UInt8(ascii: "a")...UInt8(ascii: "z")
    private static let uppercase = UInt8(ascii: "A")...UInt8(ascii: "Z")
    private static let digit = UInt8(ascii: "0")...UInt8(ascii: "9")

    private static func humps(in raw: String) -> [Int] {
        var humps: [Int] = []
        var (beforePrevious, previous): (UInt8, UInt8) = (0, 0)
        for (offset, byte) in raw.utf8.enumerated() {
            guard byte < 0x80 else { return [] }
            switch (beforePrevious, previous, byte) {
            case (_, lowercase, uppercase), (_, digit, lowercase), (_, digit, uppercase):
                humps.append(offset)
            case (uppercase, uppercase, lowercase):
                humps.append(offset - 1)
            default:
                break
            }
            (beforePrevious, previous) = (previous, byte)
        }
        return humps
    }
}

enum LauncherMatch {
    enum Outcome: Sendable, Equatable {
        case exact
        case scored(score: Int, skipped: Int)

        var value: Int {
            switch self {
            case .exact: Int.max
            case .scored(let score, _): score
            }
        }
    }

    static let space: UInt16 = 0x20

    private static let precheckThreshold = 2

    static func match(_ query: SearchText, in target: SearchText) -> Outcome? {
        let q = query.units
        let t = target.units
        guard !q.isEmpty else { return nil }
        if q == t { return .exact }
        let letters = q.reduce(0) { isSeparator($1) ? $0 : $0 + 1 }
        guard letters <= t.count else { return nil }
        if letters > precheckThreshold, !isRoughSubsequence(q, of: t) { return nil }
        return align(q, t, humps: target.humps, letters: letters)
    }

    static func isSeparator(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09, 0x0A, 0x20, 0x28, 0x29, 0x2D, 0x2E, 0x2F, 0x5B, 0x5D: true
        default: false
        }
    }

    private static func isRoughSubsequence(_ q: [UInt16], of t: [UInt16]) -> Bool {
        var position = 0
        for unit in q {
            if isSeparator(unit) {
                if position < t.count, isSeparator(t[position]) { position += 1 }
                continue
            }
            guard let found = t[position...].firstIndex(of: unit) else { return false }
            position = found + 1
        }
        return true
    }

    private static func align(_ q: [UInt16], _ t: [UInt16], humps: [Int], letters: Int) -> Outcome? {
        let width = t.count
        var previous = [Int](repeating: .min, count: width)
        var current = [Int](repeating: .min, count: width)
        var anchor = -1
        var rowStart = 0
        var rowEnd = 0
        var matched = 0
        var skipped = 0

        for unit in q {
            let unitIsSeparator = isSeparator(unit)
            let lower = anchor + 1
            let upper = min(width, width - (letters - 1 - matched))
            var first = -1
            var gapBest = Int.min
            if lower < upper {
                for column in lower..<upper {
                    if anchor >= 0, column - 2 >= anchor { gapBest = max(gapBest, previous[column - 2]) }
                    let candidate = t[column]
                    let same = candidate == unit
                    let bothSeparators = !same && unitIsSeparator && isSeparator(candidate)
                    guard same || bothSeparators else {
                        current[column] = .min
                        continue
                    }
                    let points =
                        bothSeparators
                        ? 1 : (anchor < 0 && column == 0 ? 4 : wordPoints(t, column, humps: humps))
                    if anchor < 0 {
                        current[column] = points
                    } else {
                        var best = Int.min
                        let adjacent = previous[column - 1]
                        if adjacent != .min { best = adjacent + points }
                        if gapBest != .min { best = max(best, gapBest + points - 1) }
                        current[column] = best
                    }
                    if first < 0 { first = column }
                }
            }
            if first >= 0 {
                anchor = first
                matched += 1
                rowStart = lower
                rowEnd = upper
                swap(&previous, &current)
            } else if unitIsSeparator {
                skipped += 1
            } else {
                return nil
            }
        }
        guard anchor >= 0 else { return nil }
        let best = previous[rowStart..<rowEnd].max() ?? .min
        return best == .min ? nil : .scored(score: best, skipped: skipped)
    }

    private static func wordPoints(_ t: [UInt16], _ column: Int, humps: [Int]) -> Int {
        (isSeparator(t[column - 1]) && !isSeparator(t[column])) || humps.contains(column) ? 3 : 2
    }
}

enum SearchSensitivity: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    static let `default`: Self = .medium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    func accepts(_ outcome: LauncherMatch.Outcome, queryLength: Int) -> Bool {
        guard case .scored(let score, let skipped) = outcome else { return true }
        let length = queryLength - skipped
        switch self {
        case .low: return true
        case .medium: return Double(score) >= 1.5 * Double(length - 2) + 4
        case .high: return score > 2 * length
        }
    }
}
