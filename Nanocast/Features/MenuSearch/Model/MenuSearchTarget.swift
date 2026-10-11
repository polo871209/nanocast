import Foundation

enum MenuSearchTarget: Hashable, Sendable {
    case searchable(name: String)
    case excluded(name: String)
    case selfTarget
    case menuLess(name: String)
    case noApplication

    static func classify(
        appName: String?, isSelf: Bool, hasMenuBar: Bool, isExcluded: Bool
    ) -> Self {
        guard let appName else { return .noApplication }
        if isSelf { return .selfTarget }
        if isExcluded { return .excluded(name: appName) }
        guard hasMenuBar else { return .menuLess(name: appName) }
        return .searchable(name: appName)
    }
}
