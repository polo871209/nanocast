import Foundation

enum WindowCycle: String, CaseIterable, Identifiable, Sendable {
    case off
    case sizes
    case displays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "None"
        case .sizes: "Cycle ½, ⅓ and ⅔"
        case .displays: "Cycle displays"
        }
    }

    var detail: String {
        switch self {
        case .off: "Repeating a half keeps the same frame."
        case .sizes: "Repeating a half steps through ⅓ and ⅔."
        case .displays: "Repeating a half moves it across your displays."
        }
    }
}
