import Foundation

nonisolated enum FileToolArchiveEngine {
    private static let tar = "/usr/bin/tar"
    private static let skipped = ["--exclude", ".DS_Store", "--exclude", "__MACOSX"]

    static func run(_ request: FileToolRequest) throws {
        switch request.kind {
        case .zip: try pack(request, format: ["--format", "zip"])
        case .tarGzip: try pack(request, format: ["-z"])
        case .extract: try extract(request)
        default: throw FileToolEngine.Failure.unsupported
        }
    }

    private static func pack(_ request: FileToolRequest, format: [String]) throws {
        guard !request.sources.isEmpty else { throw FileToolEngine.Failure.unsupported }
        let members = request.sources.flatMap { ["-C", $0.deletingLastPathComponent().path, $0.lastPathComponent] }
        try FileToolEngine.runTool(
            tar, ["-c", "--no-mac-metadata"] + format + skipped + ["-f", request.destination.path] + members)
    }

    private static func extract(_ request: FileToolRequest) throws {
        guard let source = request.sources.first, let archive = FileToolArchive(fileName: source.lastPathComponent)
        else { throw FileToolEngine.Failure.unsupported }
        if archive == .gzip {
            try FileToolEngine.runTool("/usr/bin/gunzip", ["-c", source.path], output: request.destination)
            return
        }
        let manager = FileManager.default
        let unpacked = request.destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: unpacked, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: unpacked) }
        try FileToolEngine.runTool(tar, ["-x"] + skipped + ["-f", source.path, "-C", unpacked.path])
        let entries = try manager.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: [.isDirectoryKey])
        if entries.count == 1, let only = entries.first,
            (try? only.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        {
            try manager.moveItem(at: only, to: request.destination)
        } else {
            try manager.moveItem(at: unpacked, to: request.destination)
        }
    }
}
