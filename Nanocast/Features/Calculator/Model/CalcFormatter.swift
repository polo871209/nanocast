import Foundation

enum CalcFormatter {
    static func expression(_ query: String) -> String {
        query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "*", with: "×")
            .replacingOccurrences(of: "/", with: "÷")
    }

    static func display(_ value: Double) -> String {
        grouped(copyText(value))
    }

    private static let maxExactInteger = 9_007_199_254_740_992.0

    static func copyText(_ value: Double) -> String {
        let v = value == 0 ? 0 : value
        if v.rounded() == v && abs(v) <= maxExactInteger {
            return String(Int64(v))
        }
        return String(format: "%.10g", v)
    }

    static func currency(_ value: Double) -> String {
        let magnitude = abs(value)
        // Below ~1e-9 the digits are noise, and a literal "0.00" avoids `%.2f`'s "-0.00".
        guard magnitude >= 1e-9 else { return "0.00" }
        guard magnitude < 0.01 else { return String(format: "%.2f", value) }
        var text = String(format: "%.\(3 - Int(floor(log10(magnitude))))f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    static func compoundFeetInches(_ feet: Double) -> String {
        let sign = feet < 0 ? "-" : ""
        let magnitude = abs(feet)
        let wholeFeet = magnitude.rounded(.towardZero)
        let inches = (magnitude - wholeFeet) * 12
        let feetPart =
            wholeFeet == 0 ? "" : "\(sign)\(display(wholeFeet)) \(wholeFeet == 1 ? "foot" : "feet")"
        let inchText = display(inches)
        let inchPart = "\(inchText) \(inchText == "1" ? "inch" : "inches")"
        if feetPart.isEmpty { return "\(sign)\(inchPart)" }
        return "\(feetPart) \(inchPart)"
    }

    static func timespan(_ seconds: Double) -> String {
        guard seconds.isFinite else { return display(seconds) }
        let sign = seconds < 0 ? "-" : ""
        var remainder = abs(seconds).rounded()
        var parts: [String] = []
        for step in timespanSteps where remainder >= step.seconds {
            let count = (remainder / step.seconds).rounded(.towardZero)
            remainder -= count * step.seconds
            parts.append("\(grouped(String(format: "%.0f", count))) \(step.symbol)")
        }
        if parts.isEmpty { return "\(display(seconds)) s" }
        return sign + parts.joined(separator: " ")
    }

    private static let timespanSteps: [(seconds: Double, symbol: String)] = [
        (604800, "wk"), (86400, "day"), (3600, "hr"), (60, "min"), (1, "s")
    ]

    static func grouped(_ text: String) -> String {
        let bytes = text.utf8
        guard !bytes.contains(101), !bytes.contains(69) else { return text }
        let signCount = bytes.first == 45 ? 1 : 0
        let integer = bytes.prefix { $0 != 46 }
        guard integer.count - signCount > 3 else { return text }
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count + integer.count / 3)
        for (index, byte) in bytes.enumerated() {
            if index > signCount, index < integer.count, (integer.count - index) % 3 == 0 {
                output.append(44)
            }
            output.append(byte)
        }
        return String(bytes: output, encoding: .utf8)!
    }
}
