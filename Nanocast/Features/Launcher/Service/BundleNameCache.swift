import Foundation

struct BundleNameCache: Sendable {
    private struct Entry: Sendable {
        let modified: Date?
        let names: [String]
    }

    private let languages: [String]
    private let previous: [String: Entry]
    private var current: [String: Entry] = [:]

    init() {
        languages = []
        previous = [:]
    }

    init(reusing cache: BundleNameCache, languages: [String]) {
        self.languages = languages
        previous = cache.languages == languages ? cache.current : [:]
    }

    mutating func names(for url: URL, base: String, developmentRegion: String?) -> [String] {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        if let cached = previous[url.path], cached.modified == modified {
            current[url.path] = cached
            return cached.names
        }
        let names = BundleLocalization.names(
            for: url, base: base, developmentRegion: developmentRegion, languages: languages)
        current[url.path] = Entry(modified: modified, names: names)
        return names
    }
}
