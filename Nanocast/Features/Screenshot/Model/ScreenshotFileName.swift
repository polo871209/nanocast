import Foundation

enum ScreenshotFileName {
    static func name(at date: Date, in timeZone: TimeZone, isTaken: (String) -> Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stem = String(
            format: "Screenshot %04d-%02d-%02d at %02d.%02d.%02d", parts.year ?? 0, parts.month ?? 0,
            parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        var candidate = stem + ".png"
        var number = 2
        while isTaken(candidate) {
            candidate = "\(stem) (\(number)).png"
            number += 1
        }
        return candidate
    }
}
