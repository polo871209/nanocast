import Foundation

/// A Tinycast `MAJOR.MINOR.PATCH`, plus the Nanocast release `-REVISION` built on it.
struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let revision: Int

    init?(_ text: String) {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if body.first == "v" { body = body.dropFirst() }

        let parts = body.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
            let major = Self.number(numbers[0]),
            let minor = Self.number(numbers[1]),
            let patch = Self.number(numbers[2]),
            let revision = parts.count == 2 ? Self.number(parts[1]) : 0
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.revision = revision
    }

    var description: String {
        let base = "\(major).\(minor).\(patch)"
        return revision == 0 ? base : "\(base)-\(revision)"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch, lhs.revision) < (rhs.major, rhs.minor, rhs.patch, rhs.revision)
    }

    private static func number(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}

extension AppVersion: Codable {
    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = AppVersion(text) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(), debugDescription: "Not a version: \(text)")
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
