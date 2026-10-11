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
                label: "Settings & Shortcuts", symbol: "slider.horizontal.3",
                subpath: "")
        case .clipboard:
            return .init(
                label: "Clipboard History", symbol: "doc.on.clipboard",
                subpath: "clipboard")
        case .notes:
            return .init(label: "Notes", symbol: "note.text", subpath: "notes")
        case .learning:
            return .init(
                label: "Launcher Learning", symbol: "chart.line.uptrend.xyaxis",
                subpath: "learning")
        }
    }

    /// Nil where a number would say nothing.
    func countText(_ count: Int) -> String? {
        switch self {
        case .configuration: return nil
        case .clipboard: return count == 1 ? "1 clip" : "\(count) clips"
        case .notes: return count == 1 ? "1 note" : "\(count) notes"
        case .learning: return count == 1 ? "1 record" : "\(count) records"
        }
    }

    static let all = Set(BackupCategory.allCases)

    static func ordered(_ selection: Set<BackupCategory>) -> [BackupCategory] {
        allCases.filter(selection.contains)
    }
}
