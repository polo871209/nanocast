import Foundation

enum CalcToken: Equatable, Sendable {
    case number(Double)
    case compactNumber(Double)
    case intLiteral(UInt64, base: CalcNumberBase)
    case ident(String)
    case op(CalcOperator)
    case arrow
    case comma
}

extension [CalcToken] {
    /// The runs `pattern` leaves open — each `nil` is one — or nil unless the whole query matches.
    func operands(of pattern: [CalcToken?]) -> [[CalcToken]]? {
        var operands: [[CalcToken]] = []
        var cursor = 0
        for (index, part) in pattern.enumerated() {
            if let fixed = part {
                guard cursor < count, self[cursor] == fixed else { return nil }
                cursor += 1
                continue
            }
            var end = count
            if index + 1 < pattern.count, let next = pattern[index + 1] {
                guard cursor < count, let found = self[(cursor + 1)...].firstIndex(of: next) else {
                    return nil
                }
                end = found
            }
            guard end > cursor else { return nil }
            operands.append(Array(self[cursor..<end]))
            cursor = end
        }
        return cursor == count ? operands : nil
    }
}
