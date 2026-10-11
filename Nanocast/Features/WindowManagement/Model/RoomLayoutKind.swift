// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import Foundation

enum RoomLayoutKind: String, Codable, CaseIterable, Sendable {
    case auto
    case focus
    case stack
    case columns
    case grid
    case custom
    case saved

    var title: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .focus: String(localized: "Focus")
        case .stack: String(localized: "Stack")
        case .columns: String(localized: "Columns")
        case .grid: String(localized: "Grid")
        case .custom: String(localized: "Custom")
        case .saved: String(localized: "As Arranged")
        }
    }
}
