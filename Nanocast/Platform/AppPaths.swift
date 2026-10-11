import Foundation

enum AppPaths {
    static func caches(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.nanocast.app"
    ) -> URL {
        root(.cachesDirectory, bundleID: bundleID)
    }

    static func applicationSupport(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.nanocast.app"
    ) -> URL {
        root(.applicationSupportDirectory, bundleID: bundleID)
    }

    static func settingsFile(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.nanocast.app"
    ) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config", directoryHint: .isDirectory)
            .appending(path: configFolderName(bundleID: bundleID), directoryHint: .isDirectory)
            .appending(path: "settings.json", directoryHint: .notDirectory)
    }

    static func contentFolder(
        _ chosen: String?, named name: String,
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.nanocast.app"
    ) -> URL {
        guard let chosen, isFolderPath(chosen) else {
            return applicationSupport(bundleID: bundleID).appending(path: name, directoryHint: .isDirectory)
        }
        return URL(filePath: (chosen as NSString).expandingTildeInPath, directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
    }

    static func contentFolderSetting(
        for url: URL, named name: String,
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.nanocast.app"
    ) -> String? {
        let chosen = url.standardizedFileURL.resolvingSymlinksInPath()
        let standard = contentFolder(nil, named: name, bundleID: bundleID).resolvingSymlinksInPath()
        guard chosen.path != standard.path else { return nil }
        return (chosen.path as NSString).abbreviatingWithTildeInPath
    }

    static func isFolderPath(_ path: String) -> Bool {
        path.hasPrefix("/") || path.hasPrefix("~/")
    }

    private static func configFolderName(bundleID: String) -> String {
        let stable = "com.nanocast.app"
        if bundleID == stable { return "nanocast" }
        guard bundleID.hasPrefix(stable + ".") else { return bundleID }
        return "nanocast-" + bundleID.dropFirst(stable.count + 1)
    }

    private static func root(
        _ directory: FileManager.SearchPathDirectory, bundleID: String
    ) -> URL {
        let url = FileManager.default
            .urls(for: directory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
