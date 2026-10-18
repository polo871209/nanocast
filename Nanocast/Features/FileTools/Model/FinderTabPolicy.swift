import Foundation

struct FinderFocus: Equatable, Sendable {
    let role: String
    let subrole: String?
    let selectionCount: Int?
}

enum FinderTabPolicy {
    static let tabKeyCode: Int64 = 48

    private static let modifierMask: UInt64 = 0x0002_0000 | 0x0004_0000 | 0x0008_0000 | 0x0010_0000 | 0x0080_0000
    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    private static let textSubroles: Set<String> = ["AXSearchField", "AXSecureTextField"]
    private static let fileViewRoles: Set<String> = [
        "AXOutline", "AXTable", "AXList", "AXBrowser", "AXGroup", "AXScrollArea"
    ]

    static func isCandidate(keyCode: Int64, flags: UInt64) -> Bool {
        keyCode == tabKeyCode && flags & modifierMask == 0
    }

    static func opensFileTools(keyCode: Int64, flags: UInt64, focus: FinderFocus?) -> Bool {
        guard isCandidate(keyCode: keyCode, flags: flags), let focus else { return false }
        if textRoles.contains(focus.role) { return false }
        if let subrole = focus.subrole, textSubroles.contains(subrole) { return false }
        guard fileViewRoles.contains(focus.role), let count = focus.selectionCount else { return false }
        return count > 0
    }
}
