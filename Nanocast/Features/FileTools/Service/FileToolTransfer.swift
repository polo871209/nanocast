import Foundation

nonisolated enum FileToolTransfer {
    enum Mode: Sendable {
        case move, copy
    }

    enum Conflict: Sendable {
        case replace, keepBoth
    }

    static func conflicts(_ sources: [URL], in folder: URL) -> [URL] {
        sources.filter { source in
            let target = folder.appendingPathComponent(source.lastPathComponent)
            return !isSameItem(source, target) && FileManager.default.fileExists(atPath: target.path)
        }
    }

    /// Returns where each source landed. A replaced item goes to the Trash, so no file is lost.
    @concurrent
    static func run(_ mode: Mode, _ sources: [URL], into folder: URL, conflict: Conflict) async throws -> [URL] {
        let manager = FileManager.default
        var landed: [URL] = []
        for source in sources {
            try Task.checkCancellation()
            var target = folder.appendingPathComponent(source.lastPathComponent)
            if isSameItem(source, target) {
                guard mode == .copy else {
                    landed.append(source)
                    continue
                }
                target = freeName(for: source, in: folder)
            } else if manager.fileExists(atPath: target.path) {
                switch conflict {
                case .replace: try manager.trashItem(at: target, resultingItemURL: nil)
                case .keepBoth: target = freeName(for: source, in: folder)
                }
            }
            switch mode {
            case .move: try manager.moveItem(at: source, to: target)
            case .copy: try manager.copyItem(at: source, to: target)
            }
            landed.append(target)
        }
        return landed
    }

    private static func isSameItem(_ source: URL, _ target: URL) -> Bool {
        source.standardizedFileURL.resolvingSymlinksInPath() == target.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func freeName(for source: URL, in folder: URL) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var number = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }
}
