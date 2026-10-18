import Foundation

struct PathFacts: Hashable, Sendable {
    let path: String
    var exists = true
    var isSymbolicLink = false
    var volumeIsReadOnly = false
    var isSystemRestricted = false
    var isUserImmutable = false
    var isOwnedByCurrentUser = true
    var parentIsWritable = true
    var parentIsSticky = false
}

struct UninstallEnvironment: Hashable, Sendable {
    let home: String
    let hasFullDiskAccess: Bool
}

enum UninstallProtection: String, Hashable, Sendable, CaseIterable {
    case removable
    case systemProtected
    case userLocked
    case notOwned
    case needsFullDiskAccess
    case parentNotWritable
    case missing

    var isRemovable: Bool { self == .removable }

    var lockReason: String? {
        switch self {
        case .removable:
            return nil
        case .systemProtected:
            return "Part of macOS and protected by the system."
        case .userLocked:
            return "Locked in Finder. Unlock it in Get Info, then try again."
        case .notOwned:
            return "Owned by another user, in a folder that only lets owners remove things."
        case .needsFullDiskAccess:
            return """
                Needs Full Disk Access, which Nanocast doesn’t request. \
                Grant it in System Settings › Privacy & Security to include this item.
                """
        case .parentNotWritable:
            return """
                Its enclosing folder isn’t writable by you, and Nanocast never asks for an \
                administrator password.
                """
        case .missing:
            return "No longer on disk."
        }
    }
}

enum UninstallProtectionRules {
    static func classify(_ facts: PathFacts, environment: UninstallEnvironment) -> UninstallProtection {
        guard facts.exists else { return .missing }
        if facts.isSystemRestricted || facts.volumeIsReadOnly { return .systemProtected }
        if facts.isUserImmutable { return .userLocked }
        if !environment.hasFullDiskAccess,
            isTCCProtected(path: facts.path, home: environment.home)
        {
            return .needsFullDiskAccess
        }
        if !facts.parentIsWritable { return .parentNotWritable }
        if facts.parentIsSticky, !facts.isOwnedByCurrentUser { return .notOwned }
        return .removable
    }

    static func isTCCProtected(path: String, home: String) -> Bool {
        let relative = tccRelativePrefixes.contains { path.hasPrefix(home + "/" + $0) }
        return relative || path.hasPrefix("/Library/Application Support/com.apple.TCC")
    }

    static let tccRelativePrefixes: [String] = [
        "Library/Containers/",
        "Library/Group Containers/",
        "Library/Cookies/",
        "Library/Safari",
        "Library/Mail",
        "Library/Messages",
        "Library/Calendars",
        "Library/Suggestions",
        "Library/HomeKit",
        "Library/IdentityServices",
        "Library/Sharing",
        "Library/Biome",
        "Library/Trial",
        "Library/Metadata/CoreSpotlight",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/MobileSync",
        "Library/Application Support/com.apple.sharedfilelist/"
    ]
}
