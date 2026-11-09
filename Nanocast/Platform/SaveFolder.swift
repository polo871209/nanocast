import Foundation

enum SaveFolder {
    static func url(for setting: String?) -> URL {
        guard let setting, AppPaths.isFolderPath(setting) else { return desktop }
        return URL(filePath: (setting as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }

    static func setting(for chosen: URL) -> String? {
        let chosen = chosen.standardizedFileURL.resolvingSymlinksInPath()
        return chosen.path == desktop.resolvingSymlinksInPath().path
            ? nil : (chosen.path as NSString).abbreviatingWithTildeInPath
    }

    private static var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}
