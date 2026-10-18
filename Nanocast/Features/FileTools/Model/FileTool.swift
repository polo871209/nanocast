import Foundation

struct FileTool: Identifiable, Hashable, Sendable {
    enum Section: CaseIterable, Sendable {
        case convert, tools, actions

        var title: String {
            switch self {
            case .convert: "Convert"
            case .tools: "Tools"
            case .actions: "Actions"
            }
        }
    }

    enum Output: Equatable, Sendable {
        case file(extension: String)
        case folder
        case text
        case none
    }

    let kind: FileToolKind
    let target: FileToolTarget?
    let slot: FileToolOptionSlot?
    let fields: [FileToolField]

    init(
        _ kind: FileToolKind, target: FileToolTarget? = nil, slot: FileToolOptionSlot? = nil,
        fields: [FileToolField] = []
    ) {
        self.kind = kind
        self.target = target
        self.slot = slot
        self.fields = fields
    }

    var id: String {
        switch (kind, target) {
        case (.convertImage, .image(let format)?): "convertImage.\(format.rawValue)"
        case (.convertAudio, .audio(let format)?): "convertAudio.\(format.rawValue)"
        case (.convertVideo, .video(let format)?): "convertVideo.\(format.rawValue)"
        default: kind.rawValue
        }
    }

    var options: [FileToolOption] { slot?.choices ?? [] }

    var isFinderOnly: Bool {
        switch kind {
        case .zip, .tarGzip, .combinePDFs, .imagesToPDF: true
        default: false
        }
    }

    var combinesSources: Bool { isFinderOnly }

    var runsInHelper: Bool {
        switch kind {
        case .pinImage, .copyPath, .airDrop, .moveTo, .copyTo, .copyText: false
        default: true
        }
    }

    var section: Section {
        switch kind {
        case .convertImage, .convertAudio, .convertVideo, .pdfToImages, .pdfToText, .imagesToPDF: .convert
        case .pinImage, .copyPath, .airDrop, .moveTo, .copyTo, .copyText, .readQRCode: .actions
        default: .tools
        }
    }

    var timeout: Duration {
        switch kind {
        case .convertImage, .compressImage, .compressImageToSize, .resizeImage, .stripMetadata, .readQRCode:
            .seconds(120)
        default: .seconds(3600)
        }
    }

    var title: String {
        switch (kind, target) {
        case (.convertImage, .image(let format)?): "Convert to \(format.displayName)"
        case (.convertAudio, .audio(let format)?): "Convert to \(format.displayName)"
        case (.convertVideo, .video(let format)?): "Convert to \(format.displayName)"
        case (.compressImage, _): "Compress"
        case (.compressImageToSize, _): "Compress to Size"
        case (.resizeImage, _): "Resize"
        case (.stripMetadata, _): "Strip Metadata"
        case (.copyText, _): "Copy Text"
        case (.readQRCode, _): "Read QR Code"
        case (.pinImage, _): "Pin Image"
        case (.zip, _): "Compress to ZIP"
        case (.tarGzip, _): "Compress to TAR.GZ"
        case (.extract, _): "Extract"
        case (.changeSpeed, _): "Change Speed"
        case (.changeSpeedAndPitch, _): "Change Speed and Pitch"
        case (.trimAudio, _): "Trim"
        case (.combinePDFs, _): "Combine PDFs"
        case (.imagesToPDF, _): "Images to PDF"
        case (.splitPDF, _): "Split PDF"
        case (.extractPages, _): "Extract Pages"
        case (.compressPDF, _): "Compress PDF"
        case (.pdfToImages, _): "PDF to Images"
        case (.pdfToText, _): "PDF to Text"
        case (.copyPath, _): "Copy Path"
        case (.airDrop, _): "AirDrop"
        case (.moveTo, _): "Move to…"
        case (.copyTo, _): "Copy to…"
        case (.convertImage, _), (.convertAudio, _), (.convertVideo, _): "Convert"
        }
    }

    var searchText: String {
        switch target {
        case .image(let format)? where kind == .convertImage: "\(title) \(format.fileExtension)"
        default: title
        }
    }

    var verb: String {
        switch kind {
        case .convertImage, .convertAudio, .convertVideo, .pdfToImages, .pdfToText, .imagesToPDF: "Convert"
        case .compressImage, .compressImageToSize, .compressPDF, .zip, .tarGzip: "Compress"
        case .resizeImage: "Resize"
        case .stripMetadata: "Strip"
        case .copyText, .readQRCode, .copyPath, .copyTo: "Copy"
        case .pinImage: "Pin"
        case .extract, .extractPages: "Extract"
        case .changeSpeed, .changeSpeedAndPitch: "Change"
        case .trimAudio: "Trim"
        case .combinePDFs: "Combine"
        case .splitPDF: "Split"
        case .airDrop: "Send"
        case .moveTo: "Move"
        }
    }

    var systemImage: String {
        switch kind {
        case .convertImage, .convertAudio, .convertVideo, .pdfToImages, .pdfToText: "arrow.triangle.2.circlepath"
        case .compressImage, .compressImageToSize, .compressPDF: "arrow.down.right.and.arrow.up.left"
        case .resizeImage: "arrow.up.left.and.arrow.down.right"
        case .stripMetadata: "eye.slash"
        case .copyText: "text.viewfinder"
        case .readQRCode: "qrcode.viewfinder"
        case .pinImage: "pin"
        case .zip, .tarGzip: "archivebox"
        case .extract: "shippingbox.and.arrow.backward"
        case .changeSpeed, .changeSpeedAndPitch: "gauge.with.dots.needle.67percent"
        case .trimAudio: "scissors"
        case .combinePDFs, .imagesToPDF: "doc.on.doc"
        case .splitPDF: "square.split.2x1"
        case .extractPages: "doc.badge.arrow.up"
        case .copyPath: "doc.on.clipboard"
        case .airDrop: "airplayaudio"
        case .moveTo: "folder"
        case .copyTo: "plus.rectangle.on.folder"
        }
    }

    func output(for source: URL) -> Output {
        switch kind {
        case .convertImage, .compressImage, .compressImageToSize, .resizeImage, .stripMetadata, .imagesToPDF:
            if case .image(let format)? = target { return .file(extension: format.fileExtension) }
            return .file(extension: "pdf")
        case .convertAudio:
            if case .audio(let format)? = target { return .file(extension: format.fileExtension) }
            return .none
        case .convertVideo:
            if case .video(let format)? = target { return .file(extension: format.fileExtension) }
            return .none
        case .trimAudio:
            let ext = source.pathExtension.lowercased()
            return .file(extension: FileToolAudioFormat.trimPassthroughExtensions.contains(ext) ? ext : "m4a")
        case .changeSpeed, .changeSpeedAndPitch: return .file(extension: source.pathExtension.lowercased())
        case .zip: return .file(extension: "zip")
        case .tarGzip: return .file(extension: "tar.gz")
        case .combinePDFs, .extractPages, .compressPDF: return .file(extension: "pdf")
        case .pdfToText: return .file(extension: "txt")
        case .splitPDF, .pdfToImages: return .folder
        case .extract: return FileToolArchive(fileName: source.lastPathComponent) == .gzip ? .file(extension: "") : .folder
        case .readQRCode: return .text
        case .copyText, .pinImage, .copyPath, .airDrop, .moveTo, .copyTo: return .none
        }
    }

    func outputStem(sources: [URL], option: FileToolOption?, parameters: FileToolParameters) -> String {
        let first = sources.first ?? URL(fileURLWithPath: "/")
        let stem = first.deletingPathExtension().lastPathComponent
        switch (kind, option) {
        case (.compressImage, _), (.compressPDF, _): return "\(stem) compressed"
        case (.compressImageToSize, _): return "\(stem) \(parameters.sizeLabel)"
        case (.resizeImage, .longestEdge(let edge)?): return "\(stem) \(edge)px"
        case (.stripMetadata, _): return "\(stem) no metadata"
        case (.changeSpeed, .speed(let speed)?), (.changeSpeedAndPitch, .speed(let speed)?):
            return "\(stem) \(speed.label)"
        case (.trimAudio, _): return "\(stem) trimmed"
        case (.zip, _), (.tarGzip, _):
            return sources.count == 1 ? first.lastPathComponent : "Archive"
        case (.extract, _): return FileToolArchive.baseName(of: first.lastPathComponent)
        case (.combinePDFs, _), (.imagesToPDF, _): return "\(stem) combined"
        case (.splitPDF, _): return "\(stem) pages"
        case (.extractPages, _): return "\(stem) pages \(parameters.pagesLabel)"
        case (.pdfToImages, _): return "\(stem) images"
        default: return stem
        }
    }

    func request(
        option: FileToolOption?, parameters: FileToolParameters, sources: [URL], destination: URL
    ) -> FileToolRequest {
        let chosen = option.flatMap { options.contains($0) ? $0 : nil } ?? slot?.defaultOption
        return FileToolRequest(
            kind: kind, target: target, option: chosen, parameters: parameters, sources: sources, destination: destination)
    }

    func option(after current: FileToolOption?, backwards: Bool) -> FileToolOption? {
        guard !options.isEmpty else { return nil }
        let index = current.flatMap(options.firstIndex(of:)) ?? 0
        let step = backwards ? options.count - 1 : 1
        return options[(index + step) % options.count]
    }
}
