import Foundation
import Synchronization

enum CalcDateFormatters {
    private enum Layout: Hashable {
        case pattern(String)
        case template(String)
    }

    private struct Key: Hashable {
        let layout: Layout
        let zone: String
        let locale: String
        /// Not in `locale.identifier`, so a 24-hour switch would otherwise hit a stale formatter.
        let hourCycle: Locale.HourCycle
        let calendar: Calendar.Identifier
    }

    private static let cache = Mutex<[Key: DateFormatter]>([:])

    static func string(from date: Date, calendar: Calendar, zone: TimeZone, pattern: String) -> String {
        string(from: date, calendar: calendar, zone: zone, layout: .pattern(pattern))
    }

    /// For clock times: a `j` lets the locale and the 24-hour switch choose between `h a` and `HH`.
    static func string(from date: Date, calendar: Calendar, zone: TimeZone, template: String) -> String {
        string(from: date, calendar: calendar, zone: zone, layout: .template(template))
    }

    private static func string(
        from date: Date, calendar: Calendar, zone: TimeZone, layout: Layout
    ) -> String {
        let locale = calendar.locale ?? Locale(identifier: "en_US")
        let key = Key(
            layout: layout, zone: zone.identifier, locale: locale.identifier,
            hourCycle: locale.hourCycle, calendar: calendar.identifier)

        return cache.withLock { cache in
            if let formatter = cache[key] { return formatter.string(from: date) }

            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = zone
            formatter.locale = locale
            switch layout {
            case .pattern(let pattern): formatter.dateFormat = pattern
            case .template(let template):
                formatter.setLocalizedDateFormatFromTemplate(template)
                // ICU puts U+202F before AM/PM; a plain space keeps a pasted answer plain text.
                formatter.dateFormat = formatter.dateFormat.replacing("\u{202F}", with: " ")
            }
            if cache.count >= 64 { cache.removeAll(keepingCapacity: true) }
            cache[key] = formatter
            return formatter.string(from: date)
        }
    }
}
