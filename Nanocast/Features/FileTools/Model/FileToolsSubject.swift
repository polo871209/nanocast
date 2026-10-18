import UniformTypeIdentifiers

struct FileToolsSubject: Equatable, Sendable {
    enum Origin: Equatable, Sendable {
        case search, finder
    }

    struct Item: Equatable, Sendable {
        let url: URL
        let isDirectory: Bool

        var name: String { url.lastPathComponent }

        var type: UTType? {
            isDirectory ? .folder : UTType(filenameExtension: url.pathExtension)
        }
    }

    let items: [Item]
    let origin: Origin

    init(items: [Item], origin: Origin) {
        self.items = items
        self.origin = origin
    }

    init(url: URL, isDirectory: Bool, origin: Origin) {
        self.init(items: [Item(url: url, isDirectory: isDirectory)], origin: origin)
    }

    var urls: [URL] { items.map(\.url) }

    var isBatch: Bool { items.count > 1 }

    var first: Item? { items.first }
}
