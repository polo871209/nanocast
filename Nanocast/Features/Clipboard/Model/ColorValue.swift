import Foundation

struct ColorValue: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    var hasAlpha: Bool { (alpha * 255).rounded() < 255 }
}

extension ColorValue {
    init(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1) {
        let saturation = min(max(saturation, 0), 1)
        let lightness = min(max(lightness, 0), 1)
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base = lightness - chroma / 2
        let (red, green, blue): (Double, Double, Double) =
            switch sector {
            case ..<1: (chroma, second, 0)
            case ..<2: (second, chroma, 0)
            case ..<3: (0, chroma, second)
            case ..<4: (0, second, chroma)
            case ..<5: (second, 0, chroma)
            default: (chroma, 0, second)
            }
        self.init(red: red + base, green: green + base, blue: blue + base, alpha: alpha)
    }

    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let chroma = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let span = 1 - abs(2 * lightness - 1)
        guard chroma > 0, span > 0 else { return (0, 0, lightness) }
        let hue: Double =
            switch maximum {
            case red: 60 * ((green - blue) / chroma).truncatingRemainder(dividingBy: 6)
            case green: 60 * ((blue - red) / chroma + 2)
            default: 60 * ((red - green) / chroma + 4)
            }
        return (
            hue < 0 ? hue + 360 : hue, min(chroma / span, 1), lightness
        )
    }

    private static let detectionLimit = 64

    private static let scanLimit = 2048

    static func parse(_ text: String) -> ColorValue? {
        guard text.utf8.count <= scanLimit, couldBeColor(text.utf8) else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= detectionLimit else { return nil }
        if token.hasPrefix("#") { return parseHex(token.dropFirst()) }
        return parseFunctional(token)
    }

    private static func couldBeColor(_ bytes: String.UTF8View) -> Bool {
        guard let first = bytes.first(where: { !isSpace($0) }),
            let last = bytes.reversed().first(where: { !isSpace($0) })
        else { return false }
        if first == UInt8(ascii: "#") { return isHex(last) }
        return isLetter(first) && last == UInt8(ascii: ")")
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (byte >= 0x09 && byte <= 0x0D)
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "z")
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
            || ((byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "f"))
    }

    private static func parseHex(_ digits: Substring) -> ColorValue? {
        guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let channels: [Double]
        switch digits.count {
        case 3, 4:
            channels = digits.compactMap { $0.hexDigitValue.map { Double($0 * 17) / 255 } }
        case 6, 8:
            channels = stride(from: 0, to: digits.count, by: 2).compactMap { offset in
                let start = digits.index(digits.startIndex, offsetBy: offset)
                let end = digits.index(start, offsetBy: 2)
                return UInt8(digits[start..<end], radix: 16).map { Double($0) / 255 }
            }
        default:
            return nil
        }
        guard channels.count == digits.count / (digits.count <= 4 ? 1 : 2) else { return nil }
        return ColorValue(
            red: channels[0], green: channels[1], blue: channels[2],
            alpha: channels.count == 4 ? channels[3] : 1)
    }

    private static func parseFunctional(_ token: String) -> ColorValue? {
        guard let open = token.firstIndex(of: "("), token.hasSuffix(")") else { return nil }
        let function = token[token.startIndex..<open].lowercased()
        let body = token[token.index(after: open)..<token.index(before: token.endIndex)]
        guard let parts = arguments(of: body), parts.count == 3 || parts.count == 4,
            let alpha = parts.count == 4 ? component(parts[3], scale: 1) : 1
        else { return nil }
        switch function {
        case "rgb", "rgba":
            guard let red = component(parts[0], scale: 255),
                let green = component(parts[1], scale: 255),
                let blue = component(parts[2], scale: 255)
            else { return nil }
            return ColorValue(red: red, green: green, blue: blue, alpha: alpha)
        case "hsl", "hsla":
            guard let hue = angle(parts[0]), let saturation = percentage(parts[1]),
                let lightness = percentage(parts[2])
            else { return nil }
            return ColorValue(
                hue: hue, saturation: saturation, lightness: lightness, alpha: alpha)
        case "oklch":
            guard let lightness = component(parts[0], scale: 1),
                let chroma = component(parts[1], scale: 1),
                let hue = angle(parts[2])
            else { return nil }
            return ColorValue(
                lightness: lightness, chroma: parts[1].hasSuffix("%") ? chroma * 0.4 : chroma,
                hue: hue, alpha: alpha)
        default:
            return nil
        }
    }

    private static func component(_ text: String, scale: Double) -> Double? {
        guard text.allSatisfy({ $0.isASCII && ($0.isNumber || ".-%".contains($0)) }) else {
            return nil
        }
        let value =
            text.hasSuffix("%")
            ? Double(text.dropLast()).map { $0 / 100 } : Double(text).map { $0 / scale }
        return value.flatMap { $0.isFinite ? $0 : nil }
    }

    private static func percentage(_ text: String) -> Double? {
        text.hasSuffix("%") ? component(text, scale: 1) : nil
    }

    private static func arguments(of body: Substring) -> [String]? {
        let parts: [String]
        if body.contains(",") {
            guard !body.contains("/") else { return nil }
            parts = body.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            let sides = body.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" })
                .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            switch sides.count {
            case 1 where sides[0].count == 3: parts = sides[0]
            case 2 where sides[0].count == 3 && sides[1].count == 1: parts = sides[0] + sides[1]
            default: return nil
            }
        }
        return parts.allSatisfy { !$0.isEmpty } ? parts : nil
    }

    private static func angle(_ text: String) -> Double? {
        let digits = text.lowercased().hasSuffix("deg") ? String(text.dropLast(3)) : text
        guard let degrees = Double(digits), degrees.isFinite else { return nil }
        return degrees.truncatingRemainder(dividingBy: 360) + (degrees < 0 ? 360 : 0)
    }
}
