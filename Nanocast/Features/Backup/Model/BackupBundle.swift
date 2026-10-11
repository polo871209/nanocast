import Foundation

struct BackupBundle: Sendable {
    enum LearningPart: String, CaseIterable, Sendable {
        case ranking
        case emoji
        case calculator
    }

    let root: URL

    init(root: URL) {
        self.root = root
    }

    var manifestURL: URL { root.appendingPathComponent("manifest.json") }
    var settingsURL: URL { root.appendingPathComponent("settings.json") }

    private func directory(for category: BackupCategory) -> URL {
        let subpath = category.descriptor.subpath
        guard !subpath.isEmpty else { return root }
        return root.appendingPathComponent(subpath, isDirectory: true)
    }

    var clipboardItemsURL: URL { directory(for: .clipboard).appendingPathComponent("items.jsonl") }
    var clipboardImagesDirectory: URL {
        directory(for: .clipboard).appendingPathComponent("images", isDirectory: true)
    }
    var notesDirectory: URL { directory(for: .notes) }

    func learningURL(_ part: LearningPart) -> URL {
        directory(for: .learning).appendingPathComponent("\(part.rawValue).json")
    }

    func prepare(_ categories: Set<BackupCategory>) throws {
        try create(root)
        if categories.contains(.clipboard) { try create(clipboardImagesDirectory) }
        if categories.contains(.notes) { try create(notesDirectory) }
        if categories.contains(.learning) { try create(directory(for: .learning)) }
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func writeManifest(_ manifest: BackupManifest) throws {
        try write(try Self.encoder.encode(manifest), to: manifestURL)
    }

    @discardableResult
    func writeDocument(
        title: String, extension ext: String, contents: String, in directory: URL
    )
        throws -> String
    {
        let name = uniqueName(base: Self.sanitized(title), extension: ext, in: directory)
        try write(Data(contents.utf8), to: directory.appendingPathComponent(name))
        return name
    }

    struct ClipboardWriter: ~Copyable {
        private let handle: FileHandle
        private let encoder: JSONEncoder

        init(url: URL) throws {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
        }

        func write(_ item: BackupClipboardItem) throws {
            var line = try encoder.encode(item)
            line.append(0x0A)
            try handle.write(contentsOf: line)
        }

        deinit { try? handle.close() }
    }

    func clipboardWriter() throws -> ClipboardWriter {
        try ClipboardWriter(url: clipboardItemsURL)
    }

    func clipboardItems() -> some Sequence<BackupClipboardItem> {
        let data = (try? Data(contentsOf: clipboardItemsURL, options: .mappedIfSafe)) ?? Data()
        return data.split(separator: 0x0A, omittingEmptySubsequences: true)
            .lazy
            .compactMap { try? Self.decoder.decode(BackupClipboardItem.self, from: Data($0)) }
    }

    func readManifest() throws(BackupFormatError) -> BackupManifest {
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? Self.decoder.decode(BackupManifest.self, from: data)
        else { throw .unreadable }
        guard manifest.format == BackupManifest.currentFormat else {
            throw .unsupportedFormat(found: manifest.format)
        }
        return manifest
    }

    func clipboardImageURL(named name: String) -> URL? {
        guard Self.isSafeName(name) else { return nil }
        let url = clipboardImagesDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func documents(in directory: URL, extension ext: String) -> [(name: String, contents: String)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().compactMap { name in
            guard Self.isSafeName(name), (name as NSString).pathExtension == ext,
                let contents = try? String(
                    contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            else { return nil }
            return (name, contents)
        }
    }

    func decodeLearning<Value: Decodable>(_ part: LearningPart, as type: Value.Type) -> Value? {
        guard let data = try? Data(contentsOf: learningURL(part)) else { return nil }
        return try? Self.decoder.decode(Value.self, from: data)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func sanitized(_ title: String) -> String {
        let cleaned = title.components(separatedBy: Self.forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = String(cleaned.drop { $0 == "." }.prefix(120))
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && name.rangeOfCharacter(from: Self.forbidden) == nil
    }

    private static let forbidden = CharacterSet(charactersIn: "/:\\\0")

    private func uniqueName(base: String, extension ext: String, in directory: URL) -> String {
        var candidate = "\(base).\(ext)"
        var suffix = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            suffix += 1
            candidate = "\(base) \(suffix).\(ext)"
        }
        return candidate
    }

    private func create(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
