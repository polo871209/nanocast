import UniformTypeIdentifiers

enum FileToolCatalog {
    struct Context: Sendable {
        /// The type identifiers ImageIO reads on this Mac.
        var decodableImages: Set<String>
        var canPickFolders: Bool
    }

    static func tools(for subject: FileToolsSubject, context: Context) -> [FileTool] {
        guard let first = subject.first else { return [] }
        var tools = tools(for: first, context: context)
        if subject.isBatch {
            let shared = subject.items.dropFirst().map { Set(self.tools(for: $0, context: context).map(\.id)) }
            tools.removeAll { tool in shared.contains { !$0.contains(tool.id) } }
        }
        if subject.origin == .finder {
            tools += [FileTool(.zip), FileTool(.tarGzip)]
            if subject.items.allSatisfy({ $0.type?.conforms(to: .pdf) == true }) {
                tools.append(FileTool(.combinePDFs))
            }
            if subject.items.allSatisfy({ isRaster($0, context: context) }) {
                tools.append(FileTool(.imagesToPDF, target: .image(.pdf)))
            }
        }
        return ordered(tools)
    }

    static func tool(id: FileTool.ID, for item: FileToolsSubject.Item, context: Context) -> FileTool? {
        tools(for: item, context: context).first { $0.id == id }
    }

    static func tools(for item: FileToolsSubject.Item, context: Context) -> [FileTool] {
        var tools: [FileTool] = []
        if !item.isDirectory, let type = item.type {
            let ext = item.url.pathExtension.lowercased()
            if type.conforms(to: .pdf) {
                tools += pdfTools
            } else if type.conforms(to: .image), type.conforms(to: .svg) || context.decodableImages.contains(type.identifier) {
                tools += imageTools(type: type)
            } else if FileToolAudioFormat.readableExtensions.contains(ext) {
                tools += audioTools(extension: ext)
            } else if type.conforms(to: .movie), let format = FileToolVideoFormat(fileExtension: ext) {
                tools += videoTools(format)
            }
            if FileToolArchive(fileName: item.name) != nil {
                tools.append(FileTool(.extract))
            }
        }
        tools += [FileTool(.copyPath), FileTool(.airDrop)]
        if context.canPickFolders {
            tools += [FileTool(.moveTo), FileTool(.copyTo)]
        }
        return ordered(tools)
    }

    private static let pdfTools = [
        FileTool(.pdfToImages, slot: .pageFormat), FileTool(.pdfToText), FileTool(.splitPDF),
        FileTool(.extractPages, fields: [.pages]), FileTool(.compressPDF), FileTool(.copyText)
    ]

    private static func imageTools(type: UTType) -> [FileTool] {
        let isVector = type.conforms(to: .svg)
        let source = FileToolImageFormat(type: type)
        let kept = FileToolTarget.image(source ?? .png)
        var tools = FileToolImageFormat.convertTargets
            .filter { $0 != source }
            .map { FileTool(.convertImage, target: .image($0), slot: isVector ? .scale : nil) }
        if let source, source.isLossy {
            tools.append(FileTool(.compressImage, target: kept, slot: .quality))
        }
        if !isVector {
            let lossy = source.flatMap { $0.isLossy ? $0 : nil } ?? .jpeg
            tools.append(FileTool(.compressImageToSize, target: .image(lossy), fields: [.targetSize]))
        }
        tools.append(FileTool(.resizeImage, target: kept, slot: .longestEdge))
        if !isVector {
            tools += [FileTool(.stripMetadata, target: kept), FileTool(.copyText), FileTool(.readQRCode)]
        }
        tools.append(FileTool(.pinImage))
        return tools
    }

    private static func audioTools(extension ext: String) -> [FileTool] {
        let source = FileToolAudioFormat(fileExtension: ext)
        let converts = FileToolAudioFormat.allCases
            .filter { $0 == .m4a || $0 != source }
            .map { FileTool(.convertAudio, target: .audio($0), slot: $0 == .m4a ? .codec : nil) }
        return converts + [FileTool(.trimAudio, fields: [.start, .end])]
    }

    private static func videoTools(_ source: FileToolVideoFormat) -> [FileTool] {
        let converts = FileToolVideoFormat.allCases
            .filter { $0 != source }
            .map { FileTool(.convertVideo, target: .video($0)) }
        return converts + [FileTool(.changeSpeed, slot: .speed), FileTool(.changeSpeedAndPitch, slot: .speed)]
    }

    private static func isRaster(_ item: FileToolsSubject.Item, context: Context) -> Bool {
        guard !item.isDirectory, let type = item.type, type.conforms(to: .image), !type.conforms(to: .pdf) else {
            return false
        }
        return !type.conforms(to: .svg) && context.decodableImages.contains(type.identifier)
    }

    private static func ordered(_ tools: [FileTool]) -> [FileTool] {
        let order = FileTool.Section.allCases
        return tools.enumerated()
            .sorted { lhs, rhs in
                let left = order.firstIndex(of: lhs.element.section) ?? 0
                let right = order.firstIndex(of: rhs.element.section) ?? 0
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }
}
