import Foundation

enum ScreenshotFileName {
    enum Kind {
        case screenshot
        case recording(ScreenRecordingFormat)

        fileprivate var prefix: String {
            switch self {
            case .screenshot: return "Screenshot"
            case .recording: return "Screen Recording"
            }
        }

        fileprivate var fileExtension: String {
            switch self {
            case .screenshot: return "png"
            case .recording(let format): return format.fileExtension
            }
        }
    }

    static func name(of kind: Kind, at date: Date, in timeZone: TimeZone, isTaken: (String) -> Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stem = String(
            format: "%@ %04d-%02d-%02d at %02d.%02d.%02d", kind.prefix, parts.year ?? 0, parts.month ?? 0,
            parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        var candidate = "\(stem).\(kind.fileExtension)"
        var number = 2
        while isTaken(candidate) {
            candidate = "\(stem) (\(number)).\(kind.fileExtension)"
            number += 1
        }
        return candidate
    }
}
