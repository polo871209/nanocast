import Foundation

struct NoteMarkdown: Sendable, Equatable {
    struct Line: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case blank
            case paragraph
            case heading(level: Int)
            case bullet
            case ordered(number: Int)
            case task(checked: Bool)
            case quote(depth: Int)
            case rule
            case fenceOpen(language: String?)
            case fenceClose
            case code
            case table

            var isList: Bool {
                switch self {
                case .bullet, .ordered, .task: true
                default: false
                }
            }

            var isFenced: Bool {
                switch self {
                case .fenceOpen, .fenceClose, .code: true
                default: false
                }
            }
        }

        let kind: Kind
        let range: NSRange
        let contentRange: NSRange
        let markerRange: NSRange?
        let checkboxRange: NSRange?
        let level: Int
    }

    struct Inline: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case strong, emphasis, strongEmphasis, strikethrough, code
            case link(destination: String)
            case autolink
        }

        let kind: Kind
        let range: NSRange
        let contentRange: NSRange
        let markerRanges: [NSRange]
    }

    let units: [UInt16]
    let lines: [Line]
    let fenceBlocks: [ClosedRange<Int>]

    static let empty = NoteMarkdown(units: [], lines: [], fenceBlocks: [])

    func inlines(of line: Line) -> [Inline] {
        switch line.kind {
        case .paragraph, .heading, .quote, .bullet, .ordered, .task:
            NoteInlineScanner(units: units)
                .inlines(in: line.contentRange.location..<NSMaxRange(line.contentRange))
        default:
            []
        }
    }

    func lineIndex(at location: Int) -> Int? {
        guard let last = lines.last, 0...NSMaxRange(last.range) ~= location else { return nil }
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].range.location <= location {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    func lineIndexes(intersecting range: NSRange) -> Range<Int> {
        guard let first = lineIndex(at: range.location) else { return 0..<0 }
        guard range.length > 0, let last = lineIndex(at: NSMaxRange(range) - 1) else {
            return first..<(first + 1)
        }
        return first..<(max(first, last) + 1)
    }
}
