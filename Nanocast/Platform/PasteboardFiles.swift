import AppKit

/// The files a pasteboard names; `NSURL` reading picks a representation of its own choosing.
enum PasteboardFiles {
    private static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    static func write(_ url: URL, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.fileURL, .string], owner: nil)
        pasteboard.setData(url.dataRepresentation, forType: .fileURL)
        // Both types: a file-taking app receives the file, a text field receives the path.
        pasteboard.setString(url.path, forType: .string)
    }

    static func urls(on pasteboard: NSPasteboard) -> [URL] {
        urls(on: pasteboard, limit: .max) { _ in true }
    }

    static func urls(
        on pasteboard: NSPasteboard, limit: Int, matching predicate: (URL) -> Bool
    ) -> [URL] {
        guard limit > 0 else { return [] }
        var matches: [URL] = []
        var hasFileURL = false
        for item in pasteboard.pasteboardItems ?? [] {
            guard let url = url(from: item) else { continue }
            hasFileURL = true
            guard predicate(url) else { continue }
            matches.append(url)
            if matches.count == limit { return matches }
        }
        guard !hasFileURL,
            let paths = pasteboard.propertyList(forType: legacyFilenames) as? [String]
        else { return matches }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard predicate(url) else { continue }
            matches.append(url)
            if matches.count == limit { return matches }
        }
        return matches
    }

    /// `public.file-url` arrives as UTF-8 data on most boards and as a string on some.
    private static func url(from item: NSPasteboardItem) -> URL? {
        if let data = item.data(forType: .fileURL),
            let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL
        {
            return url
        }
        guard let string = item.string(forType: .fileURL), let url = URL(string: string),
            url.isFileURL
        else { return nil }
        return url
    }
}
