import AppKit
import AVFoundation
import CoreImage
import ImageIO
import PDFKit
import Synchronization
import UniformTypeIdentifiers

@main
struct FileToolsHelperTests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    static let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("nanocast-file-tools-\(ProcessInfo.processInfo.processIdentifier)")

    /// A 1×1 lossless WebP: ImageIO reads WebP but cannot write one.
    static let webp = "UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA=="

    static let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20">
        <rect width="40" height="20" fill="#e84"/><circle cx="20" cy="10" r="6" fill="#248"/></svg>
        """

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let png = url("source.png")
        let bmp = url("source.bmp")
        let jpeg = url("source.jpg")
        let vector = url("source.svg")
        let lossless = url("source.webp")
        writeImage(width: 400, height: 200, to: png, format: .png, alpha: true)
        writeImage(width: 64, height: 32, to: bmp, format: .bmp, alpha: false)
        writeImage(width: 600, height: 300, to: jpeg, format: .jpeg, alpha: false, gps: true)
        try? Data(svg.utf8).write(to: vector)
        try? Data(base64Encoded: webp)?.write(to: lossless)

        await conversions(of: [png, bmp, jpeg, vector, lossless])
        await sizes(png: png, vector: vector)
        await compression(jpeg: jpeg)
        await metadata(jpeg: jpeg)
        await transparency(png: png)
        await targetSize(jpeg: jpeg, png: png)
        await qrCode()
        await archives()
        await pdfs(png: png, jpeg: jpeg)
        await audio()
        await video()
        await worker(png: png)
        await transfers()

        print("file-tools-helper-test: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    static func request(
        _ kind: FileToolKind, _ output: FileToolImageFormat, option: FileToolOption? = nil, source: URL,
        destination: String
    ) -> FileToolRequest {
        request(kind, target: .image(output), option: option, sources: [source], destination: destination)
    }

    static func request(
        _ kind: FileToolKind, target: FileToolTarget? = nil, option: FileToolOption? = nil,
        parameters: FileToolParameters = FileToolParameters(), sources: [URL], destination: String
    ) -> FileToolRequest {
        FileToolRequest(
            kind: kind, target: target, option: option, parameters: parameters, sources: sources,
            destination: url(destination))
    }

    @discardableResult
    static func run(_ request: FileToolRequest) async -> Bool {
        do {
            try await FileToolEngine.run(request)
            return true
        } catch {
            return false
        }
    }

    static func properties(of url: URL) -> (type: String, width: Int, height: Int, info: [CFString: Any])? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let type = CGImageSourceGetType(source) as String?,
            let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let width = info[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = info[kCGImagePropertyPixelHeight] as? Int ?? 0
        return (type, width, height, info)
    }

    static func conversions(of sources: [URL]) async {
        for source in sources {
            let input = source.pathExtension
            for output in FileToolImageFormat.convertTargets {
                let name = "\(input)-to.\(output.fileExtension)"
                let option: FileToolOption? = input == "svg" ? .scale(2) : nil
                let converted = await run(
                    request(.convertImage, output, option: option, source: source, destination: name))
                expect(converted, "\(input) converts to \(output.displayName)")
                if output == .pdf {
                    let document = CGPDFDocument(url(name) as CFURL)
                    expect(document?.numberOfPages == 1, "\(input) to PDF holds one page")
                } else {
                    let read = properties(of: url(name))
                    expect(read?.type == output.identifier, "\(input) to \(output.displayName) reads back as that type")
                    expect((read?.width ?? 0) > 0, "\(input) to \(output.displayName) has pixels")
                }
            }
        }
        let missing = await run(request(.convertImage, .png, source: url("missing.heic"), destination: "missing.png"))
        expect(!missing, "a missing source fails")
    }

    static func sizes(png: URL, vector: URL) async {
        await run(request(.resizeImage, .png, option: .longestEdge(100), source: png, destination: "resized.png"))
        let resized = properties(of: url("resized.png"))
        expect(resized?.width == 100 && resized?.height == 50, "Resize fits the longest edge and keeps the ratio")

        await run(request(.resizeImage, .png, option: .longestEdge(4000), source: png, destination: "unscaled.png"))
        expect(properties(of: url("unscaled.png"))?.width == 400, "Resize never enlarges a raster image")

        await run(request(.convertImage, .png, option: .scale(2), source: vector, destination: "vector-2x.png"))
        let doubled = properties(of: url("vector-2x.png"))
        expect(doubled?.width == 80 && doubled?.height == 40, "SVG at 2× doubles its declared size")

        await run(request(.convertImage, .png, option: .scale(4), source: vector, destination: "vector-4x.png"))
        expect(properties(of: url("vector-4x.png"))?.width == 160, "SVG at 4× quadruples its declared size")

        await run(request(.resizeImage, .png, option: .longestEdge(1000), source: vector, destination: "vector-big.png"))
        expect(properties(of: url("vector-big.png"))?.width == 1000, "a vector resize renders at the requested edge")
    }

    static func compression(jpeg: URL) async {
        await run(request(.compressImage, .jpeg, option: .quality(.high), source: jpeg, destination: "high.jpg"))
        await run(request(.compressImage, .jpeg, option: .quality(.small), source: jpeg, destination: "small.jpg"))
        let high = (try? url("high.jpg").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let small = (try? url("small.jpg").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        expect(high > 0 && small > 0 && small < high, "Small writes a smaller file than High")
    }

    static func metadata(jpeg: URL) async {
        expect(properties(of: jpeg)?.info[kCGImagePropertyGPSDictionary] != nil, "the fixture carries GPS")
        await run(request(.convertImage, .png, source: jpeg, destination: "kept.png"))
        await run(request(.convertImage, .heic, source: jpeg, destination: "kept.heic"))
        expect(properties(of: url("kept.heic"))?.info[kCGImagePropertyGPSDictionary] != nil, "Convert keeps GPS")
        await run(request(.stripMetadata, .jpeg, source: jpeg, destination: "stripped.jpg"))
        let stripped = properties(of: url("stripped.jpg"))
        expect(stripped?.info[kCGImagePropertyGPSDictionary] == nil, "Strip Metadata drops GPS")
        let exif = stripped?.info[kCGImagePropertyExifDictionary] as? [CFString: Any]
        expect(exif?[kCGImagePropertyExifUserComment] == nil, "Strip Metadata drops EXIF")
        expect(stripped?.width == 600, "Strip Metadata keeps the pixels")
    }

    static func transparency(png: URL) async {
        await run(request(.convertImage, .jpeg, source: png, destination: "flat.jpg"))
        await run(request(.convertImage, .tiff, source: png, destination: "clear.tiff"))
        expect(properties(of: url("flat.jpg"))?.info[kCGImagePropertyHasAlpha] as? Bool != true, "JPEG drops alpha")
        expect(properties(of: url("clear.tiff"))?.info[kCGImagePropertyHasAlpha] as? Bool == true, "TIFF keeps alpha")
    }

    static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    static func targetSize(jpeg: URL, png: URL) async {
        let large = url("large.jpg")
        writeImage(width: 2400, height: 1600, to: large, format: .jpeg, alpha: false)
        for target in [200_000, 60_000, 20_000] {
            var parameters = FileToolParameters()
            parameters.targetBytes = target
            let name = "fit-\(target).jpg"
            let fitted = await run(
                request(
                    .compressImageToSize, target: .image(.jpeg), parameters: parameters, sources: [large],
                    destination: name))
            expect(fitted && size(of: url(name)) <= target, "Compress to Size stays within \(target) bytes")
            expect(size(of: url(name)) > target / 4, "Compress to Size does not waste the budget at \(target) bytes")
        }
        var tiny = FileToolParameters()
        tiny.targetBytes = 1000
        let fromPNG = await run(
            request(.compressImageToSize, target: .image(.jpeg), parameters: tiny, sources: [png], destination: "tiny.jpg"))
        expect(fromPNG && size(of: url("tiny.jpg")) <= 1000, "a PNG compresses to a JPEG under its size by scaling down")
    }

    static func qrCode() async {
        let code = url("code.png")
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data("https://nanocast.app".utf8), forKey: "inputMessage")
        let scaled = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let padded = scaled.composited(over: CIImage(color: .white).cropped(to: scaled.extent.insetBy(dx: -40, dy: -40)))
        let context = CIContext()
        let image = context.createCGImage(padded, from: padded.extent)!
        let destination = CGImageDestinationCreateWithURL(code as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)

        let read = await run(request(.readQRCode, sources: [code], destination: "code.txt"))
        let payload = try? String(contentsOf: url("code.txt"), encoding: .utf8)
        expect(read && payload == "https://nanocast.app", "Read QR Code returns the payload")

        let plain = url("source.png")
        let none = await run(request(.readQRCode, sources: [plain], destination: "none.txt"))
        let empty = try? String(contentsOf: url("none.txt"), encoding: .utf8)
        expect(none && empty == "", "an image without a code returns no text")
    }

    static func archives() async {
        let box = url("box")
        try? FileManager.default.createDirectory(at: box.appendingPathComponent("inner"), withIntermediateDirectories: true)
        try? Data("alpha".utf8).write(to: box.appendingPathComponent("a.txt"))
        try? Data("beta".utf8).write(to: box.appendingPathComponent("inner/b.txt"))
        try? Data("junk".utf8).write(to: box.appendingPathComponent(".DS_Store"))
        let loose = url("loose.txt")
        try? Data("gamma".utf8).write(to: loose)

        let zipped = await run(request(.zip, sources: [box, loose], destination: "Archive.zip"))
        expect(zipped, "ZIP packs a folder and a file")
        let tarred = await run(request(.tarGzip, sources: [box], destination: "box.tar.gz"))
        expect(tarred, "TAR.GZ packs a folder")

        let fromZip = await run(request(.extract, sources: [url("Archive.zip")], destination: "Archive"))
        expect(fromZip, "ZIP extracts")
        expect(
            (try? String(contentsOf: url("Archive/box/inner/b.txt"), encoding: .utf8)) == "beta",
            "ZIP keeps the folder tree")
        expect((try? String(contentsOf: url("Archive/loose.txt"), encoding: .utf8)) == "gamma", "ZIP keeps the loose file")
        expect(!FileManager.default.fileExists(atPath: url("Archive/box/.DS_Store").path), "ZIP leaves out .DS_Store")
        let listing = (try? FileManager.default.contentsOfDirectory(atPath: url("Archive").path)) ?? []
        expect(!listing.contains("__MACOSX") && !listing.contains { $0.hasPrefix("._") }, "ZIP adds no Mac metadata")

        let fromTar = await run(request(.extract, sources: [url("box.tar.gz")], destination: "box-out"))
        expect(fromTar, "TAR.GZ extracts")
        expect(
            (try? String(contentsOf: url("box-out/a.txt"), encoding: .utf8)) == "alpha",
            "a single top folder is lifted into the output folder")

        let gzip = Process()
        gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        gzip.arguments = ["-k", loose.path]
        try? gzip.run()
        gzip.waitUntilExit()
        let gunzipped = await run(request(.extract, sources: [url("loose.txt.gz")], destination: "loose-copy.txt"))
        expect(
            gunzipped && (try? String(contentsOf: url("loose-copy.txt"), encoding: .utf8)) == "gamma",
            "GZIP extracts the file inside")
        let broken = url("broken.zip")
        try? Data("not a zip".utf8).write(to: broken)
        let failed = await run(request(.extract, sources: [broken], destination: "broken"))
        expect(!failed, "a broken archive fails")
    }

    static func writePDF(pages: Int, to url: URL, label: String) {
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        for page in 1...pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSAttributedString(
                string: "\(label) page \(page)", attributes: [.font: NSFont.systemFont(ofSize: 18)]
            ).draw(at: CGPoint(x: 20, y: 100))
            NSGraphicsContext.current = nil
            context.endPDFPage()
        }
        context.closePDF()
    }

    static func pdfs(png: URL, jpeg: URL) async {
        let first = url("first.pdf")
        let second = url("second.pdf")
        writePDF(pages: 3, to: first, label: "First")
        writePDF(pages: 2, to: second, label: "Second")

        let combined = await run(request(.combinePDFs, sources: [first, second], destination: "combined.pdf"))
        expect(combined && PDFDocument(url: url("combined.pdf"))?.pageCount == 5, "Combine PDFs keeps every page")
        expect(
            PDFDocument(url: url("combined.pdf"))?.page(at: 3)?.string?.contains("Second page 1") == true,
            "Combine PDFs keeps the order")

        let split = await run(request(.splitPDF, sources: [first], destination: "first pages"))
        let parts = (try? FileManager.default.contentsOfDirectory(atPath: url("first pages").path).sorted()) ?? []
        expect(split && parts == ["first 1.pdf", "first 2.pdf", "first 3.pdf"], "Split PDF writes one file per page")

        var range = FileToolParameters()
        range.pages = [1, 3, 9]
        let extracted = await run(
            request(.extractPages, parameters: range, sources: [first], destination: "picked.pdf"))
        let picked = PDFDocument(url: url("picked.pdf"))
        expect(extracted && picked?.pageCount == 2, "Extract Pages skips pages past the end")
        expect(picked?.page(at: 1)?.string?.contains("First page 3") == true, "Extract Pages keeps the chosen page")
        range.pages = [7]
        let outside = await run(request(.extractPages, parameters: range, sources: [first], destination: "none.pdf"))
        expect(!outside, "Extract Pages with no page in range fails")

        let compressed = await run(request(.compressPDF, sources: [first], destination: "small.pdf"))
        expect(compressed && PDFDocument(url: url("small.pdf"))?.pageCount == 3, "Compress PDF keeps the pages")

        let images = await run(
            request(.pdfToImages, option: .pageFormat(.jpeg), sources: [first], destination: "first images"))
        let rendered = (try? FileManager.default.contentsOfDirectory(atPath: url("first images").path).sorted()) ?? []
        expect(images && rendered == ["first 1.jpg", "first 2.jpg", "first 3.jpg"], "PDF to Images writes one image per page")
        let page = properties(of: url("first images/first 1.jpg"))
        expect(page?.width == 600 && page?.height == 400, "PDF to Images renders at twice the page size")

        let text = await run(request(.pdfToText, sources: [second], destination: "second.txt"))
        let body = (try? String(contentsOf: url("second.txt"), encoding: .utf8)) ?? ""
        expect(text && body.contains("Second page 1") && body.contains("Second page 2"), "PDF to Text keeps every page")

        let album = await run(request(.imagesToPDF, target: .image(.pdf), sources: [png, jpeg], destination: "album.pdf"))
        let document = PDFDocument(url: url("album.pdf"))
        expect(album && document?.pageCount == 2, "Images to PDF writes one page per image")
        expect(document?.page(at: 1)?.bounds(for: .mediaBox).width == 600, "a page takes its image's size")

        let locked = url("missing.pdf")
        let missing = await run(request(.pdfToText, sources: [locked], destination: "missing.txt"))
        expect(!missing, "a missing PDF fails")
    }

    static func writeTone(seconds: Double, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44_100) * 0.3)
            }
        }
        try file.write(from: buffer)
    }

    static func duration(of url: URL) async -> Double {
        (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
    }

    static func audio() async {
        let tone = url("tone.wav")
        do {
            try writeTone(seconds: 2, to: tone)
        } catch {
            return expect(false, "the fixture tone writes: \(error)")
        }
        for (format, codec) in [
            (FileToolAudioFormat.m4a, FileToolAudioCodec.aac), (.m4a, .alac), (.flac, .aac), (.aiff, .aac), (.wav, .aac)
        ] {
            let name = "tone-\(codec.rawValue).\(format.fileExtension)"
            let converted = await run(
                request(.convertAudio, target: .audio(format), option: .codec(codec), sources: [tone], destination: name))
            expect(converted, "WAV converts to \(format.displayName) \(codec.displayName)")
            let length = await duration(of: url(name))
            expect(abs(length - 2) < 0.1, "\(format.displayName) \(codec.displayName) keeps the length")
        }
        let file = try? AVAudioFile(forReading: url("tone-alac.m4a"))
        expect(file?.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatAppleLossless, "ALAC is lossless")
        let aac = try? AVAudioFile(forReading: url("tone-aac.m4a"))
        expect(aac?.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC, "AAC is AAC")

        var range = FileToolParameters()
        range.start = 0.5
        range.end = 1.5
        let trimmed = await run(request(.trimAudio, parameters: range, sources: [tone], destination: "cut.wav"))
        let cut = await duration(of: url("cut.wav"))
        expect(trimmed && abs(cut - 1) < 0.05, "Trim keeps the range")
        range.start = 1.5
        range.end = nil
        let tail = await run(request(.trimAudio, parameters: range, sources: [url("tone-aac.m4a")], destination: "tail.m4a"))
        let rest = await duration(of: url("tail.m4a"))
        expect(tail && abs(rest - 0.5) < 0.1, "Trim without an end runs to the end")
        range.start = 1.5
        range.end = nil
        let flac = await run(request(.trimAudio, parameters: range, sources: [url("tone-aac.flac")], destination: "flac.m4a"))
        let flacLength = await duration(of: url("flac.m4a"))
        expect(flac && abs(flacLength - 0.5) < 0.1, "a FLAC trims to M4A")
    }

    static func writeClip(seconds: Int, to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let receiver = writer.inputPixelBufferReceiver(for: video, pixelBufferAttributes: nil)
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        let fps = 10
        for frame in 0..<(seconds * fps) {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(frame * 10 % 255), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try await receiver.append(
                CVReadOnlyPixelBuffer(unsafeBuffer: buffer),
                with: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        receiver.finish()
        await writer.finishWriting()
    }

    static func video() async {
        let silent = url("silent.mov")
        do {
            try await writeClip(seconds: 2, to: silent)
        } catch {
            return expect(false, "the fixture clip writes: \(error)")
        }
        let composition = AVMutableComposition()
        let clip = AVURLAsset(url: silent)
        let tone = AVURLAsset(url: url("tone.wav"))
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600))
        try? composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: try await clip.loadTracks(withMediaType: .video)[0], at: .zero)
        try? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: try await tone.loadTracks(withMediaType: .audio)[0], at: .zero)
        let movie = url("clip.mov")
        let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        try? await export.export(to: movie, as: .mov)
        let fixture = await duration(of: movie)
        expect(abs(fixture - 2) < 0.1, "the fixture movie lasts two seconds")

        for speed in FileToolSpeed.allCases {
            for kind in [FileToolKind.changeSpeed, .changeSpeedAndPitch] {
                let name = "clip \(speed.rawValue) \(kind.rawValue).mov"
                let changed = await run(request(kind, option: .speed(speed), sources: [movie], destination: name))
                let length = await duration(of: url(name))
                expect(changed, "\(kind.rawValue) runs at \(speed.label)")
                expect(abs(length - 2 / speed.factor) < 0.15, "\(kind.rawValue) at \(speed.label) lasts 2 s ÷ \(speed.factor)")
            }
        }
        let tracks = (try? await AVURLAsset(url: url("clip 2 changeSpeed.mov")).loadTracks(withMediaType: .audio)) ?? []
        expect(!tracks.isEmpty, "Change Speed keeps the sound")

        for format in FileToolVideoFormat.allCases where format != .mov {
            let name = "clip converted.\(format.fileExtension)"
            let converted = await run(request(.convertVideo, target: .video(format), sources: [movie], destination: name))
            let length = await duration(of: url(name))
            expect(converted && abs(length - 2) < 0.1, "a MOV converts to \(format.displayName) at its own length")
        }
        let back = await run(
            request(.convertVideo, target: .video(.mov), sources: [url("clip converted.mp4")], destination: "clip back.mov"))
        let backTracks = (try? await AVURLAsset(url: url("clip back.mov")).loadTracks(withMediaType: .audio)) ?? []
        expect(back && !backTracks.isEmpty, "an MP4 converts back to MOV and keeps the sound")
    }

    static func transfers() async {
        let manager = FileManager.default
        let from = url("transfer-from")
        let into = url("transfer-into")
        try? manager.createDirectory(at: from, withIntermediateDirectories: true)
        try? manager.createDirectory(at: into, withIntermediateDirectories: true)
        func make(_ folder: URL, _ name: String, _ text: String) -> URL {
            let file = folder.appendingPathComponent(name)
            try? Data(text.utf8).write(to: file)
            return file
        }
        func read(_ file: URL) -> String? { try? String(contentsOf: file, encoding: .utf8) }

        let note = make(from, "note.txt", "new")
        _ = make(into, "note.txt", "old")
        let other = make(from, "other.txt", "other")
        expect(
            FileToolTransfer.conflicts([note, other], in: into).map(\.lastPathComponent) == ["note.txt"],
            "only a name already in the folder is a conflict")
        expect(FileToolTransfer.conflicts([note], in: from).isEmpty, "an item is not in conflict with itself")

        let copied = try? await FileToolTransfer.run(.copy, [note, other], into: into, conflict: .keepBoth)
        expect(
            copied?.map(\.lastPathComponent) == ["note 2.txt", "other.txt"],
            "Keep Both copies under a free name and keeps the rest")
        expect(read(into.appendingPathComponent("note.txt")) == "old", "Keep Both leaves the existing item alone")
        expect(read(note) == "new", "a copy leaves the source in place")

        let moved = try? await FileToolTransfer.run(.move, [note], into: into, conflict: .keepBoth)
        expect(moved?.first?.lastPathComponent == "note 3.txt", "a move takes the next free name")
        expect(!manager.fileExists(atPath: note.path), "a move removes the source")

        let stay = try? await FileToolTransfer.run(.move, [other], into: from, conflict: .replace)
        expect(stay == [other] && read(other) == "other", "a move into its own folder changes nothing")
        let twin = try? await FileToolTransfer.run(.copy, [other], into: from, conflict: .replace)
        expect(
            twin?.first?.lastPathComponent == "other 2.txt" && read(other) == "other",
            "a copy into its own folder duplicates and never trashes the source")
    }

    static func worker(png: URL) async {
        let destination = url("worker.png")
        let job = request(.convertImage, .png, source: png, destination: "worker.png")

        let failing = URL(fileURLWithPath: "/usr/bin/false")
        do {
            try await FileToolWorker.run(job, executable: failing)
            expect(false, "a failing helper throws")
        } catch {
            expect(error is FileToolWorker.Failure, "a failing helper reports a helper failure")
        }
        expect(!FileManager.default.fileExists(atPath: destination.path), "a failed job leaves no output")

        let stub = url("stub-helper.sh")
        let script = """
            #!/bin/sh
            dest=$(printf '%s' "$1" | sed -E 's/.*"destination":"file:([^"]*)".*/\\1/' | tr -d '\\\\' | sed 's#^//##')
            echo "progress 0.25"
            echo "noise"
            printf 'progress 0.75\n'
            printf 'made' > "$dest"
            """
        try? Data(script.utf8).write(to: stub)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let reports = Reports()
        do {
            try await FileToolWorker.run(job, executable: stub) { reports.add($0) }
            let written = try? String(contentsOf: destination, encoding: .utf8)
            expect(written == "made", "the staged output moves to the destination")
        } catch {
            expect(false, "a succeeding helper finishes the job: \(error)")
        }
        expect(reports.values == [0.25, 0.75], "progress lines reach the caller and other lines are ignored")

        let text = try? await FileToolWorker.read(
            request(.readQRCode, sources: [png], destination: "ignored.txt"), executable: stub)
        expect(text == "made", "a text job returns the helper's text")
        expect(!FileManager.default.fileExists(atPath: url("ignored.txt").path), "a text job writes no file beside the source")

        do {
            try await FileToolWorker.run(job, executable: stub)
            expect(false, "a job never replaces an existing file")
        } catch {
            let kept = try? String(contentsOf: destination, encoding: .utf8)
            expect(kept == "made", "the existing file is untouched")
        }

        let slow = url("slow-helper.sh")
        try? Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to: slow)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slow.path)
        let clock = ContinuousClock()
        let started = clock.now
        do {
            try await FileToolWorker.run(
                request(.convertImage, .png, source: png, destination: "slow.png"),
                executable: slow, timeout: .milliseconds(300))
            expect(false, "a helper past its deadline fails")
        } catch {
            expect(clock.now - started < .seconds(10), "the deadline terminates the helper")
        }
    }

    static func writeImage(
        width: Int, height: Int, to url: URL, format: FileToolImageFormat, alpha: Bool, gps: Bool = false
    ) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: info)!
        for row in 0..<height {
            for column in stride(from: 0, to: width, by: 8) {
                let shade = CGFloat((row * 7 + column * 13) % 255) / 255
                context.setFillColor(red: shade, green: 1 - shade, blue: 0.5, alpha: alpha && column < width / 2 ? 0.4 : 1)
                context.fill(CGRect(x: column, y: row, width: 8, height: 1))
            }
        }
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, format.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [:]
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 25.03, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 121.56, kCGImagePropertyGPSLongitudeRef: "E"
            ]
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: "fixture"]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
    }
}

final class Reports: Sendable {
    private let stored = Mutex<[Double]>([])

    var values: [Double] { stored.withLock { $0 } }

    func add(_ value: Double) { stored.withLock { $0.append(value) } }
}
