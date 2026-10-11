import Foundation

struct UninstallTarget: Hashable, Sendable {
    let bundleURL: URL
    let bundleID: String?
    let displayName: String
    let bundleName: String?
}

enum UninstallEvidence: String, Hashable, Sendable, CaseIterable {
    case bundle
    case bundleID
    case groupContainer
    case displayName
    case binSymlink

    var label: String? {
        switch self {
        case .displayName: return "matched by name"
        case .binSymlink: return "command-line tool"
        case .bundle, .bundleID, .groupContainer: return nil
        }
    }
}

struct UninstallIdentity: Hashable, Sendable {
    let bundleID: String?
    let allowsBundleIDPrefixMatch: Bool
    let otherBundleIDs: Set<String>
    let names: [String]
    let bundleURL: URL

    static let minimumNameLength = 3

    static let reservedNames: Set<String> = [
        "apple", "application support", "application scripts", "autosave information", "caches",
        "containers", "cookies", "crashreporter", "fonts", "frameworks", "group containers",
        "httpstorages", "keychains", "launchagents", "launchdaemons", "logs", "metadata",
        "mobilesync", "preferences", "privilegedhelpertools", "scripts", "services", "sync",
        "syncservices", "webkit"
    ]

    static func make(
        target: UninstallTarget, otherAppNames: [String], otherBundleIDs: [String] = [],
        ownBundleID: String?, ownBundleURL: URL
    ) -> UninstallIdentity? {
        if let ownBundleID, let bundleID = target.bundleID,
            folded(bundleID) == folded(ownBundleID)
        {
            return nil
        }
        if target.bundleURL.standardizedFileURL == ownBundleURL.standardizedFileURL { return nil }

        let bundleID = target.bundleID.map(folded).flatMap { $0.isEmpty ? nil : $0 }
        let names = safeNames(
            displayName: target.displayName, bundleName: target.bundleName,
            otherAppNames: otherAppNames)
        guard bundleID != nil || !names.isEmpty else { return nil }

        return UninstallIdentity(
            bundleID: bundleID,
            allowsBundleIDPrefixMatch: (bundleID?.split(separator: ".").count ?? 0) >= 3,
            otherBundleIDs: Set(otherBundleIDs.map(folded)).subtracting([bundleID].compactMap { $0 }),
            names: names,
            bundleURL: target.bundleURL.standardizedFileURL)
    }

    static func safeNames(
        displayName: String, bundleName: String?, otherAppNames: [String]
    ) -> [String] {
        let taken = Set(otherAppNames.map(folded))
        var result: [String] = []
        for candidate in [displayName, bundleName].compactMap({ $0 }) {
            let name = folded(candidate)
            guard name.count >= minimumNameLength, !reservedNames.contains(name),
                !taken.contains(name), !result.contains(name)
            else { continue }
            result.append(name)
        }
        return result
    }

    static func folded(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
