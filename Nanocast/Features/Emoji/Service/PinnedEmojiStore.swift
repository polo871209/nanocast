import Foundation

@MainActor
@Observable
final class PinnedEmojiStore {
    private static let cap = 3_000

    private let fileURL: URL
    private(set) var glyphs: [String]
    private(set) var revision = 0
    @ObservationIgnored var onPersistenceFailure: (() -> Void)?

    init(fileURL: URL = AppPaths.applicationSupport().appendingPathComponent("emoji-pinned.json")) {
        self.fileURL = fileURL
        let decoded =
            (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        glyphs = Self.normalized(decoded)
    }

    func toggle(_ glyph: String) {
        guard !glyph.isEmpty else { return }
        if let index = glyphs.firstIndex(of: glyph) {
            glyphs.remove(at: index)
        } else {
            glyphs.append(glyph)
        }
        didChange()
    }

    func replace(_ imported: [String]) {
        glyphs = Self.normalized(imported)
        didChange()
    }

    func swap(_ glyph: String, with other: String) {
        guard let source = glyphs.firstIndex(of: glyph),
            let destination = glyphs.firstIndex(of: other)
        else { return }
        glyphs.swapAt(source, destination)
        didChange()
    }

    private func didChange() {
        revision &+= 1
        do {
            let data = try JSONEncoder().encode(glyphs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            onPersistenceFailure?()
        }
    }

    private static func normalized(_ glyphs: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(min(glyphs.count, cap))
        for glyph in glyphs where !glyph.isEmpty && seen.insert(glyph).inserted {
            result.append(glyph)
            if result.count == cap { break }
        }
        return result
    }
}
