import Foundation

enum RaycastScriptImport {
    private static let headSize = 8 * 1024
    private static let directivePrefix = "@raycast."
    private static let commentMarkers = ["#", "//", "--"]

    nonisolated static func scan(
        directory: URL, fileManager: FileManager = .default
    ) -> [CustomCommand] {
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return
            contents
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard isRegularFile(url) || isRegularFile(url.resolvingSymlinksInPath()),
                    let source = head(of: url)
                else { return nil }
                return command(at: url, source: source)
            }
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    nonisolated static func command(at url: URL, source: String) -> CustomCommand? {
        guard let interpreter = shebang(in: source) else { return nil }
        let directives = directives(in: source)
        guard let title = directives["title"] else { return nil }
        return CustomCommand(
            name: title,
            command: "\(interpreter) \(shellQuoted(url.path)) \"$@\"",
            requiresConfirmation: directives["needsConfirmation"] == "true",
            arguments: arguments(in: directives),
            showsOutput: showsOutput(mode: directives["mode"]),
            workingDirectory: workingDirectory(directives["currentDirectoryPath"], script: url))
    }

    private static func shebang(in source: String) -> String? {
        let first = source.prefix { !$0.isNewline }
        guard first.hasPrefix("#!") else { return nil }
        let interpreter = first.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        return interpreter.isEmpty ? nil : interpreter
    }

    private static func directives(in source: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let body = commentBody(trimmed) else { break }
            guard body.hasPrefix(directivePrefix) else { continue }
            let field = body.dropFirst(directivePrefix.count)
            guard let separator = field.firstIndex(where: \.isWhitespace) else { continue }
            let key = String(field[..<separator])
            let value = field[separator...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            values[key] = value
        }
        return values
    }

    private static func commentBody(_ line: String) -> String? {
        guard let marker = commentMarkers.first(where: line.hasPrefix) else { return nil }
        return line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
    }

    private static func showsOutput(mode: String?) -> Bool {
        mode == "compact" || mode == "fullOutput"
    }

    private static func arguments(in directives: [String: String]) -> [CustomCommandArgument] {
        (1...3).compactMap { index in
            guard let json = directives["argument\(index)"]?.data(using: .utf8),
                let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
                let placeholder = object["placeholder"] as? String, !placeholder.isEmpty
            else { return nil }
            return CustomCommandArgument(
                name: placeholder, isOptional: object["optional"] as? Bool ?? false)
        }
    }

    private static func workingDirectory(_ declared: String?, script: URL) -> String {
        let path = declared ?? script.deletingLastPathComponent().path
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func head(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard var data = try? handle.read(upToCount: headSize), !data.isEmpty else { return nil }
        if data.count == headSize, let end = data.lastIndex(of: UInt8(ascii: "\n")) {
            data = data[..<end]
        }
        return String(bytes: data, encoding: .utf8)
    }
}
