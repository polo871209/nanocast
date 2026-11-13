import Accelerate

struct RowProfile: Sendable {
    private static let maximumBins = 64
    private static let tolerance: Float = 1
    private static let stillShare = 0.98

    let rows: Int
    private let bins: Int
    private let levels: [Float]

    init(pixels: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int, ignoringRight band: Int) {
        let usable = max(width - band, 1)
        let bins = min(Self.maximumBins, usable)
        let span = usable / bins * 4
        let levels = [Float](unsafeUninitializedCapacity: height * bins) { levels, count in
            let row = UnsafeMutablePointer<Float>.allocate(capacity: span * bins)
            defer { row.deallocate() }
            let base = pixels.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                vDSP_vfltu8(base + y * bytesPerRow, 1, row, 1, vDSP_Length(span * bins))
                for bin in 0..<bins {
                    vDSP_meanv(row + bin * span, 1, levels.baseAddress! + y * bins + bin, vDSP_Length(span))
                }
            }
            count = height * bins
        }
        rows = height
        self.bins = bins
        self.levels = levels
    }

    func difference(_ row: Int, _ other: RowProfile, _ otherRow: Int, count: Int, scratch: inout [Float]) -> Float {
        let length = count * bins
        if scratch.count < length { scratch = [Float](repeating: 0, count: length) }
        var sum: Float = 0
        levels.withUnsafeBufferPointer { mine in
            other.levels.withUnsafeBufferPointer { theirs in
                vDSP_vsub(
                    mine.baseAddress! + row * bins, 1, theirs.baseAddress! + otherRow * bins, 1, &scratch, 1,
                    vDSP_Length(length))
            }
        }
        vDSP_svemg(scratch, 1, &sum, vDSP_Length(length))
        return sum / Float(length)
    }

    func matchedShare(_ rows: Range<Int>, _ other: RowProfile, shift: Int) -> Double {
        guard !rows.isEmpty else { return 0 }
        var scratch = [Float](repeating: 0, count: bins)
        let matched = rows.count(where: { matches($0, other, $0 + shift, scratch: &scratch) })
        return Double(matched) / Double(rows.count)
    }

    func matches(_ row: Int, _ other: RowProfile, _ otherRow: Int, scratch: inout [Float]) -> Bool {
        difference(row, other, otherRow, count: 1, scratch: &scratch) <= Self.tolerance
    }

    func isStill(comparedTo other: RowProfile) -> Bool {
        other.rows == rows && matchedShare(0..<rows, other, shift: 0) >= Self.stillShare
    }
}
