import UniformTypeIdentifiers

enum FileToolImageFormat: String, CaseIterable, Codable, Sendable {
    case jpeg, png, heic, avif, tiff, bmp, pdf

    static let convertTargets: [Self] = [.jpeg, .png, .heic, .avif, .tiff, .pdf]
    static let pageFormats: [Self] = [.png, .jpeg]

    init?(type: UTType) {
        guard let format = Self.allCases.first(where: { type.conforms(to: $0.type) }) else { return nil }
        self = format
    }

    var identifier: String {
        switch self {
        case .jpeg: "public.jpeg"
        case .png: "public.png"
        case .heic: "public.heic"
        case .avif: "public.avif"
        case .tiff: "public.tiff"
        case .bmp: "com.microsoft.bmp"
        case .pdf: "com.adobe.pdf"
        }
    }

    var type: UTType { UTType(importedAs: identifier) }

    var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        case .avif: "AVIF"
        case .tiff: "TIFF"
        case .bmp: "BMP"
        case .pdf: "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .avif: "avif"
        case .tiff: "tiff"
        case .bmp: "bmp"
        case .pdf: "pdf"
        }
    }

    var isLossy: Bool { self == .jpeg || self == .heic || self == .avif }

    var dropsTransparency: Bool { self == .jpeg }
}

enum FileToolAudioFormat: String, CaseIterable, Codable, Sendable {
    case m4a, wav, aiff, flac

    static let readableExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "aifc", "flac", "caf"]
    /// `AVAssetExportSession` passes these through when trimming. Everything else is re-encoded to M4A.
    static let trimPassthroughExtensions: Set<String> = ["m4a", "wav", "aif", "aiff"]

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "m4a": self = .m4a
        case "wav": self = .wav
        case "aif", "aiff": self = .aiff
        case "flac": self = .flac
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .m4a: "M4A"
        case .wav: "WAV"
        case .aiff: "AIFF"
        case .flac: "FLAC"
        }
    }

    var fileExtension: String { rawValue }
}

enum FileToolVideoFormat: String, CaseIterable, Codable, Sendable {
    case mov, mp4, m4v

    init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }

    var displayName: String {
        switch self {
        case .mov: "MOV"
        case .mp4: "MP4"
        case .m4v: "M4V"
        }
    }

    var fileExtension: String { rawValue }
}

enum FileToolAudioCodec: String, CaseIterable, Codable, Sendable {
    case aac, alac

    var displayName: String {
        switch self {
        case .aac: "AAC"
        case .alac: "ALAC"
        }
    }
}

enum FileToolSpeed: String, CaseIterable, Codable, Sendable {
    case half = "0.5"
    case oneAndHalf = "1.5"
    case double = "2"
    case quadruple = "4"

    var factor: Double { Double(rawValue) ?? 1 }

    var label: String { "\(rawValue)×" }
}

enum FileToolQuality: String, CaseIterable, Codable, Sendable {
    case high, medium, small

    var compression: Double {
        switch self {
        case .high: 0.8
        case .medium: 0.6
        case .small: 0.4
        }
    }
}

enum FileToolArchive: Equatable, Sendable {
    case zip, tar, tarGzip, gzip

    private static let suffixes: [(String, Self)] = [
        (".tar.gz", .tarGzip), (".tgz", .tarGzip), (".tar.bz2", .tar), (".tbz", .tar), (".tar.xz", .tar),
        (".txz", .tar), (".tar", .tar), (".zip", .zip), (".gz", .gzip)
    ]

    init?(fileName: String) {
        let lower = fileName.lowercased()
        guard let match = Self.suffixes.first(where: { lower.hasSuffix($0.0) && lower.count > $0.0.count }) else {
            return nil
        }
        self = match.1
    }

    static func baseName(of fileName: String) -> String {
        let lower = fileName.lowercased()
        guard let match = suffixes.first(where: { lower.hasSuffix($0.0) && lower.count > $0.0.count }) else {
            return fileName
        }
        return String(fileName.dropLast(match.0.count))
    }
}
