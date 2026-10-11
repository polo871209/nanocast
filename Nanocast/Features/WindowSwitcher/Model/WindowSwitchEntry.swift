import Foundation

struct WindowSwitchEntry: Identifiable, Hashable, Sendable {
    let handle: Int
    let appName: String
    let bundleID: String
    let iconURL: URL?
    let iconStamp: Int
    let title: String
    var isMinimized: Bool
    let appRank: Int

    var id: String { String(handle) }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? appName : title
    }

    func searchFields() -> SearchFields {
        [SearchAlias.name(displayTitle), SearchAlias.owner(appName)]
    }
}
