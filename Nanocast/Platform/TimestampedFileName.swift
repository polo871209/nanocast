import Foundation

enum TimestampedFileName {
    static func name(
        _ prefix: String, extension fileExtension: String, at date: Date, in timeZone: TimeZone,
        isTaken: (String) -> Bool
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stem = String(
            format: "%@ %04d-%02d-%02d at %02d.%02d.%02d", prefix, parts.year ?? 0, parts.month ?? 0,
            parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        var candidate = "\(stem).\(fileExtension)"
        var number = 2
        while isTaken(candidate) {
            candidate = "\(stem) (\(number)).\(fileExtension)"
            number += 1
        }
        return candidate
    }

    static func freeURL(_ prefix: String, extension fileExtension: String, in folder: URL, at date: Date) -> URL {
        let name = name(prefix, extension: fileExtension, at: date, in: .current) { candidate in
            FileManager.default.fileExists(atPath: folder.appending(path: candidate, directoryHint: .notDirectory).path)
        }
        return folder.appending(path: name, directoryHint: .notDirectory)
    }
}
