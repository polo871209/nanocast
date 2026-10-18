import Foundation

enum FileToolKind: String, CaseIterable, Codable, Sendable {
    case convertImage, compressImage, compressImageToSize, resizeImage, stripMetadata
    case copyText, readQRCode, pinImage
    case zip, tarGzip, extract
    case changeSpeed, changeSpeedAndPitch
    case convertAudio, trimAudio
    case convertVideo
    case combinePDFs, imagesToPDF, splitPDF, extractPages, compressPDF, pdfToImages, pdfToText
    case copyPath, airDrop, moveTo, copyTo
}

enum FileToolTarget: Hashable, Codable, Sendable {
    case image(FileToolImageFormat)
    case audio(FileToolAudioFormat)
    case video(FileToolVideoFormat)
}

enum FileToolOption: Hashable, Codable, Sendable {
    case quality(FileToolQuality)
    case longestEdge(Int)
    case scale(Int)
    case speed(FileToolSpeed)
    case codec(FileToolAudioCodec)
    case pageFormat(FileToolImageFormat)

    var slot: FileToolOptionSlot {
        switch self {
        case .quality: .quality
        case .longestEdge: .longestEdge
        case .scale: .scale
        case .speed: .speed
        case .codec: .codec
        case .pageFormat: .pageFormat
        }
    }

    /// The stable spelling stored in settings, such as `quality.small` or `longestEdge.1280`.
    var token: String {
        switch self {
        case .quality(let value): "quality.\(value.rawValue)"
        case .longestEdge(let value): "longestEdge.\(value)"
        case .scale(let value): "scale.\(value)"
        case .speed(let value): "speed.\(value.rawValue)"
        case .codec(let value): "codec.\(value.rawValue)"
        case .pageFormat(let value): "pageFormat.\(value.rawValue)"
        }
    }

    init?(token: String) {
        guard let dot = token.firstIndex(of: ".") else { return nil }
        let slot = token[..<dot]
        guard let option = FileToolOptionSlot(rawValue: String(slot))?.choices.first(where: { $0.token == token })
        else { return nil }
        self = option
    }

    var title: String {
        switch self {
        case .quality(.high): "High"
        case .quality(.medium): "Medium"
        case .quality(.small): "Small"
        case .longestEdge(let edge): "\(edge) px"
        case .scale(let scale): "\(scale)×"
        case .speed(let speed): speed.label
        case .codec(let codec): codec.displayName
        case .pageFormat(let format): format.displayName
        }
    }
}

enum FileToolOptionSlot: String, CaseIterable, Sendable {
    case quality, longestEdge, scale, speed, codec, pageFormat

    static let longestEdges = [3840, 2560, 1920, 1280, 640]
    static let scales = [1, 2, 4]

    var defaultOption: FileToolOption {
        switch self {
        case .quality: .quality(.medium)
        case .longestEdge: .longestEdge(1920)
        case .scale: .scale(2)
        case .speed: .speed(.double)
        case .codec: .codec(.aac)
        case .pageFormat: .pageFormat(.png)
        }
    }

    var choices: [FileToolOption] {
        switch self {
        case .quality: FileToolQuality.allCases.map(FileToolOption.quality)
        case .longestEdge: Self.longestEdges.map(FileToolOption.longestEdge)
        case .scale: Self.scales.map(FileToolOption.scale)
        case .speed: FileToolSpeed.allCases.map(FileToolOption.speed)
        case .codec: FileToolAudioCodec.allCases.map(FileToolOption.codec)
        case .pageFormat: FileToolImageFormat.pageFormats.map(FileToolOption.pageFormat)
        }
    }
}
