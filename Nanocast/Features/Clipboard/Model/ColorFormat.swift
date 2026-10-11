import Foundation

enum ColorFormat: CaseIterable, Hashable, Sendable {
    case hex
    case hexWithAlpha
    case rgba
    case hsl
    case hslWithAlpha
    case oklch

    var title: String {
        switch self {
        case .hex: return "Hex"
        case .hexWithAlpha: return "Hex with Alpha"
        case .rgba: return "RGBA"
        case .hsl: return "HSL"
        case .hslWithAlpha: return "HSL with Alpha"
        case .oklch: return "Oklch"
        }
    }

    func string(for color: ColorValue) -> String {
        switch self {
        case .hex: return ColorDigits.hex(color, includingAlpha: false)
        case .hexWithAlpha: return ColorDigits.hex(color, includingAlpha: true)
        case .rgba:
            return "rgba(\(ColorDigits.channel(color.red)), \(ColorDigits.channel(color.green)), "
                + "\(ColorDigits.channel(color.blue)), \(ColorDigits.decimal(color.alpha)))"
        case .hsl, .hslWithAlpha:
            let hsl = color.hsl
            let alpha = carriesAlpha ? ", \(ColorDigits.decimal(color.alpha))" : ""
            return "hsl(\(ColorDigits.angle(hsl.hue)), \(ColorDigits.percent(hsl.saturation)), "
                + "\(ColorDigits.percent(hsl.lightness))\(alpha))"
        case .oklch:
            let oklch = color.oklch
            return "oklch(\(ColorDigits.percent(oklch.l)) \(ColorDigits.decimal(oklch.c)) "
                + "\(ColorDigits.angle(oklch.h))\(ColorDigits.slashAlpha(color)))"
        }
    }

    static func offered(for color: ColorValue) -> [ColorFormat] {
        allCases.filter { color.hasAlpha || !$0.carriesAlpha }
    }

    static func primary(for color: ColorValue) -> ColorFormat {
        color.hasAlpha ? .hexWithAlpha : .hex
    }

    private var carriesAlpha: Bool {
        switch self {
        case .hexWithAlpha, .hslWithAlpha: return true
        default: return false
        }
    }
}

private enum ColorDigits {
    static func hex(_ color: ColorValue, includingAlpha: Bool) -> String {
        let channels = [color.red, color.green, color.blue] + (includingAlpha ? [color.alpha] : [])
        return "#" + channels.map { String(format: "%02X", channel($0)) }.joined()
    }

    static func channel(_ value: Double) -> Int { integer(value * 255) }

    static func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 1000).rounded() / 1000
        return rounded == rounded.rounded()
            ? String(integer(rounded)) : String(format: "%g", rounded)
    }

    static func percent(_ value: Double) -> String { number(value * 100) + "%" }

    static func angle(_ value: Double) -> String { number(value) + "deg" }

    static func slashAlpha(_ color: ColorValue) -> String {
        color.hasAlpha ? " / " + decimal(color.alpha) : ""
    }

    private static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let tenths = (value * 10).rounded() / 10
        return tenths == tenths.rounded() ? String(integer(tenths)) : String(format: "%.1f", tenths)
    }

    private static func integer(_ value: Double) -> Int {
        value.isFinite ? Int(value.rounded()) : 0
    }
}
