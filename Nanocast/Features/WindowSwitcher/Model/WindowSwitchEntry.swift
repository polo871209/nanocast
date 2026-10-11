import Foundation

struct WindowSwitchEntry: Identifiable, Hashable, Sendable {
    let handle: Int
    let windowID: UInt32?
    let pid: Int32
    let appName: String
    let iconURL: URL?
    let iconStamp: Int
    let title: String

    var id: Int { handle }

    var label: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != appName else { return appName }
        return "\(appName) — \(title)"
    }
}
