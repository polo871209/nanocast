import Foundation

enum FileToolOutputName {
    static func destination(
        for tool: FileTool, option: FileToolOption?, parameters: FileToolParameters = FileToolParameters(),
        sources: [URL], isTaken: (URL) -> Bool
    ) -> URL? {
        guard let source = sources.first else { return nil }
        let fileExtension: String
        switch tool.output(for: source) {
        case .file(let ext): fileExtension = ext
        case .folder: fileExtension = ""
        case .text, .none: return nil
        }
        let folder = source.deletingLastPathComponent()
        let stem = tool.outputStem(sources: sources, option: option, parameters: parameters)
        let name = { (candidate: String) in
            fileExtension.isEmpty ? candidate : "\(candidate).\(fileExtension)"
        }
        var candidate = folder.appendingPathComponent(name(stem))
        var number = 2
        while isTaken(candidate) || candidate.standardizedFileURL == source.standardizedFileURL {
            candidate = folder.appendingPathComponent(name("\(stem) \(number)"))
            number += 1
        }
        return candidate
    }
}
