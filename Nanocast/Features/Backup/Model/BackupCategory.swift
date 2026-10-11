import Foundation

enum BackupCategory: String, CaseIterable, Identifiable, Sendable {
    case configuration
    case clipboard
    case notes
    case learning

    var id: Self { self }

    struct Descriptor: Sendable {
        let label: String
        let symbol: String
        let subpath: String
    }

    var descriptor: Descriptor {
        switch self {
        case .configuration:
            return .init(
                label: String(localized: "Settings & Shortcuts"), symbol: "slider.horizontal.3",
                subpath: "")
        case .clipboard:
            return .init(
                label: String(localized: "Clipboard History"), symbol: "doc.on.clipboard",
                subpath: "clipboard")
        case .notes:
            return .init(label: String(localized: "Notes"), symbol: "note.text", subpath: "notes")
        case .learning:
            return .init(
                label: String(localized: "Launcher Learning"), symbol: "chart.line.uptrend.xyaxis",
                subpath: "learning")
        }
    }

    /// Nil where a number would say nothing.
    func countText(_ count: Int) -> String? {
        switch self {
        case .configuration: return nil
        case .clipboard: return String(localized: "\(count) clips")
        case .notes: return String(localized: "\(count) notes")
        case .learning: return String(localized: "\(count) records")
        }
    }

    static let all = Set(BackupCategory.allCases)

    static func ordered(_ selection: Set<BackupCategory>) -> [BackupCategory] {
        allCases.filter(selection.contains)
    }
}
