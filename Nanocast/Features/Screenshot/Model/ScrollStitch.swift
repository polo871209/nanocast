struct ScrollStitch: Sendable {
    enum Step: Equatable, Sendable {
        case started(rows: Range<Int>)
        case extended(keep: Int, rows: Range<Int>)
        case unchanged
        case lost
        case full
    }

    private static let stickyShare = 3
    private static let minimumOverlapShare = 10
    private static let minimumOverlap = 8
    private static let matchShare = 0.6
    private static let tieMargin: Float = 0.05

    let cap: Int
    private(set) var height = 0
    private(set) var moving: Range<Int>?
    private(set) var lastOffset = 0
    private var previous: RowProfile?

    init(cap: Int) {
        self.cap = cap
    }

    mutating func add(_ frame: RowProfile, expected: Int) -> Step {
        guard let previous else {
            let rows = 0..<min(frame.rows, cap)
            height = rows.count
            self.previous = frame
            return .started(rows: rows)
        }
        guard frame.rows == previous.rows else { return .lost }
        if previous.isStill(comparedTo: frame) { return .unchanged }
        let moving = self.moving ?? Self.moving(previous, frame)
        guard let offset = Self.offset(previous, frame, moving: moving, expected: expected) else { return .lost }
        guard height + offset <= cap else { return .full }
        let footer = frame.rows - moving.upperBound
        let keep = height - footer
        height += offset
        lastOffset = offset
        self.moving = moving
        self.previous = frame
        return .extended(keep: keep, rows: (moving.upperBound - offset)..<frame.rows)
    }

    private static func moving(_ previous: RowProfile, _ frame: RowProfile) -> Range<Int> {
        let limit = frame.rows / stickyShare
        var scratch: [Float] = []
        let header = (0..<limit).first { !previous.matches($0, frame, $0, scratch: &scratch) } ?? limit
        let footer =
            (0..<limit).first {
                let row = frame.rows - 1 - $0
                return !previous.matches(row, frame, row, scratch: &scratch)
            } ?? limit
        return header..<(frame.rows - footer)
    }

    private static func offset(_ previous: RowProfile, _ frame: RowProfile, moving: Range<Int>, expected: Int) -> Int? {
        let overlap = max(moving.count / minimumOverlapShare, minimumOverlap)
        guard moving.count > overlap else { return nil }
        var scratch: [Float] = []
        let scores = (1...(moving.count - overlap)).map { offset in
            (
                offset: offset,
                score: previous.difference(
                    moving.lowerBound + offset, frame, moving.lowerBound, count: moving.count - offset,
                    scratch: &scratch)
            )
        }
        guard let best = scores.map(\.score).min(),
            let chosen = scores.filter({ $0.score <= best + tieMargin })
                .min(by: { abs($0.offset - expected) < abs($1.offset - expected) })?.offset
        else { return nil }
        let shared = (moving.lowerBound + chosen)..<moving.upperBound
        guard previous.matchedShare(shared, frame, shift: -chosen) >= matchShare else { return nil }
        return chosen
    }
}
