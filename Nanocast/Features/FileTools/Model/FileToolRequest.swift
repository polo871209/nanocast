import Foundation

struct FileToolRequest: Codable, Equatable, Sendable {
    let kind: FileToolKind
    let target: FileToolTarget?
    let option: FileToolOption?
    let parameters: FileToolParameters
    let sources: [URL]
    let destination: URL

    func staged(at destination: URL) -> Self {
        Self(kind: kind, target: target, option: option, parameters: parameters, sources: sources, destination: destination)
    }

    var imageFormat: FileToolImageFormat? {
        if case .image(let format)? = target { return format }
        return nil
    }

    var audioFormat: FileToolAudioFormat? {
        if case .audio(let format)? = target { return format }
        return nil
    }

    var videoFormat: FileToolVideoFormat? {
        if case .video(let format)? = target { return format }
        return nil
    }
}
