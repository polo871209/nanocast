import AppKit

nonisolated enum FinderSelectionReader {
    enum Failure: Error {
        case denied
        case failed
    }

    static let bundleIdentifier = "com.apple.finder"
    private static let automationDenied = -1743

    @concurrent
    static func read() async throws -> [FileToolsSubject.Item] {
        let script = NSAppleScript(
            source: "tell application id \"\(bundleIdentifier)\" to get selection as alias list")
        var error: NSDictionary?
        guard let list = script?.executeAndReturnError(&error) else {
            let number = error?[NSAppleScript.errorNumber] as? Int
            throw number == automationDenied ? Failure.denied : Failure.failed
        }
        guard list.numberOfItems > 0 else { return [] }
        return (1...list.numberOfItems).compactMap { index in
            guard let url = list.atIndex(index)?.fileURLValue else { return nil }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileToolsSubject.Item(url: url, isDirectory: isDirectory)
        }
    }
}
