import Foundation

struct BackupClipboardItem: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case text
        case image
        case file
    }

    var kind: Kind
    var text: String?
    var imageName: String?
    var createdAt: Date
    var sourceBundleID: String?
    var pinnedAt: Date?
}
