import Foundation

enum VolumeLevel {
    static let steps = 20
    static let step = 1 / Double(steps)

    static func clamped(_ level: Double) -> Double {
        min(max(level, 0), 1)
    }

    static func stepped(_ level: Double, up: Bool) -> Double {
        let exact = clamped(level) * Double(steps)
        let line =
            up ? (exact + tolerance).rounded(.down) + 1 : (exact - tolerance).rounded(.up) - 1
        return clamped(line / Double(steps))
    }

    static func percentage(_ level: Double, locale: Locale) -> String {
        Int((clamped(level) * 100).rounded()).formatted(.percent.locale(locale))
    }

    static func symbol(level: Double, muted: Bool = false) -> String {
        let level = clamped(level)
        if muted || level == 0 { return "speaker.slash.fill" }
        return level < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }

    private static let tolerance = 1e-6
}
