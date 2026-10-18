import Foundation

enum FileToolField: String, CaseIterable, Sendable {
    case pages, start, end, targetSize

    var title: String {
        switch self {
        case .pages: "Pages"
        case .start: "Start"
        case .end: "End"
        case .targetSize: "Size"
        }
    }

    var hint: String {
        switch self {
        case .pages: "Type the pages beside the search field, such as 1-3, 5."
        case .start, .end: "Type a start, an end, or both beside the search field, such as 0:05 and 1:30."
        case .targetSize: "Type the largest size beside the search field, such as 500 KB or 2 MB."
        }
    }

    var isOptional: Bool { self == .start || self == .end }
}

struct FileToolParameters: Codable, Equatable, Sendable {
    var pages: [Int] = []
    var start: Double?
    var end: Double?
    var targetBytes: Int?
    var pagesLabel = ""
    var sizeLabel = ""
}

enum FileToolFieldError: Error, Equatable {
    case pages, time, emptyTrim, size

    var message: String {
        switch self {
        case .pages: "Type the pages as numbers and ranges, such as 1-3, 5."
        case .time: "Type a time as seconds or minutes and seconds, such as 90 or 1:30."
        case .emptyTrim: "Type a start, an end, or both, and make the end later than the start."
        case .size: "Type a size in KB or MB, such as 500 KB or 2 MB."
        }
    }
}

enum FileToolFieldParser {
    static func parameters(
        for fields: [FileToolField], values: [FileToolField: String]
    ) -> Result<FileToolParameters, FileToolFieldError> {
        var parameters = FileToolParameters()
        for field in fields {
            let text = values[field, default: ""].trimmingCharacters(in: .whitespaces)
            switch field {
            case .pages:
                guard let pages = pages(text) else { return .failure(.pages) }
                parameters.pages = pages
                parameters.pagesLabel = label(for: pages)
            case .start, .end:
                guard !text.isEmpty else { continue }
                guard let seconds = seconds(text) else { return .failure(.time) }
                if field == .start { parameters.start = seconds } else { parameters.end = seconds }
            case .targetSize:
                guard let bytes = bytes(text) else { return .failure(.size) }
                parameters.targetBytes = bytes
                parameters.sizeLabel = sizeLabel(bytes)
            }
        }
        if fields.contains(.start) {
            guard parameters.start != nil || parameters.end != nil else { return .failure(.emptyTrim) }
            if let start = parameters.start, let end = parameters.end, end <= start { return .failure(.emptyTrim) }
        }
        return .success(parameters)
    }

    static func pages(_ text: String) -> [Int]? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }
        var pages: Set<Int> = []
        for part in parts {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
                .map { Int($0.trimmingCharacters(in: .whitespaces)) }
            switch bounds.count {
            case 1:
                guard let page = bounds[0], page > 0 else { return nil }
                pages.insert(page)
            case 2:
                guard let low = bounds[0], let high = bounds[1], low > 0, high >= low, high - low < 10_000 else {
                    return nil
                }
                pages.formUnion(low...high)
            default:
                return nil
            }
        }
        return pages.sorted()
    }

    static func label(for pages: [Int]) -> String {
        var runs: [String] = []
        var index = pages.startIndex
        while index < pages.endIndex {
            var end = index
            while pages.index(after: end) < pages.endIndex, pages[pages.index(after: end)] == pages[end] + 1 {
                end = pages.index(after: end)
            }
            runs.append(end == index ? "\(pages[index])" : "\(pages[index])-\(pages[end])")
            index = pages.index(after: end)
        }
        return runs.joined(separator: ",")
    }

    static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            guard let value = Double(part), value >= 0, value.isFinite else { return nil }
            if index < parts.count - 1, value != value.rounded() { return nil }
            if index > 0, value >= 60 { return nil }
            total = total * 60 + value
        }
        return total
    }

    static func bytes(_ text: String) -> Int? {
        let lower = text.lowercased().replacingOccurrences(of: " ", with: "")
        let units: [(String, Double)] = [("mb", 1_000_000), ("m", 1_000_000), ("kb", 1000), ("k", 1000)]
        let unit = units.first { lower.hasSuffix($0.0) }
        let number = unit.map { String(lower.dropLast($0.0.count)) } ?? lower
        guard let value = Double(number), value > 0, value.isFinite else { return nil }
        let bytes = value * (unit?.1 ?? 1000)
        guard bytes >= 1000, bytes < 10_000_000_000 else { return nil }
        return Int(bytes)
    }

    static func sizeLabel(_ bytes: Int) -> String {
        if bytes >= 1_000_000, bytes % 100_000 == 0 {
            let megabytes = Double(bytes) / 1_000_000
            return megabytes == megabytes.rounded() ? "\(Int(megabytes)) MB" : "\(megabytes) MB"
        }
        return "\(bytes / 1000) KB"
    }
}
