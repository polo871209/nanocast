import Foundation
import UniformTypeIdentifiers

@main
@MainActor
struct FileToolsTests {
    static var failures = 0
    static var passes = 0

    static let context = FileToolCatalog.Context(
        decodableImages: [
            "public.jpeg", "public.png", "public.heic", "public.heif", "public.tiff", "com.microsoft.bmp",
            "org.webmproject.webp", "com.compuserve.gif", "public.avif"
        ],
        canPickFolders: true)

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func item(_ name: String, directory: Bool = false) -> FileToolsSubject.Item {
        FileToolsSubject.Item(url: URL(fileURLWithPath: "/Users/tester/Files/\(name)"), isDirectory: directory)
    }

    static func tools(
        _ names: [String], origin: FileToolsSubject.Origin = .search, context: FileToolCatalog.Context = context
    )
        -> [FileTool]
    {
        FileToolCatalog.tools(for: FileToolsSubject(items: names.map { item($0) }, origin: origin), context: context)
    }

    static func tools(_ name: String) -> [FileTool] { tools([name]) }

    static func ids(_ name: String) -> [String] { tools(name).map(\.id) }

    static func ids(_ names: [String], origin: FileToolsSubject.Origin) -> [String] {
        tools(names, origin: origin).map(\.id)
    }

    static func main() {
        imageCatalog()
        otherCatalog()
        finderCatalog()
        options()
        fields()
        outputNames()
        requests()
        archives()
        finderTab()
        print("file-tools-test: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func imageCatalog() {
        expect(
            ids("IMG.heic") == [
                "convertImage.jpeg", "convertImage.png", "convertImage.avif", "convertImage.tiff", "convertImage.pdf",
                "compressImage", "compressImageToSize", "resizeImage", "stripMetadata", "copyText", "readQRCode",
                "pinImage", "copyPath", "airDrop", "moveTo", "copyTo"
            ],
            "HEIC lists every image tool in the order Convert, Tools, Actions")
        expect(!ids("a.png").contains("convertImage.png"), "an image is never converted to its own format")
        expect(!ids("a.png").contains("compressImage"), "a lossless source offers no Compress")
        expect(ids("a.png").contains("compressImageToSize"), "a lossless source still compresses to a size")
        expect(ids("a.jpg").contains("compressImage"), "a JPEG offers Compress")
        expect(ids("a.JPG") == ids("a.jpeg"), "the extension's case and spelling do not change the list")
        expect(ids("a.webp").contains("convertImage.png"), "WebP input converts though macOS cannot write WebP")
        expect(ids("a.bmp").contains("convertImage.jpeg"), "BMP input converts")
        expect(
            ids("logo.svg") == [
                "convertImage.jpeg", "convertImage.png", "convertImage.heic", "convertImage.avif", "convertImage.tiff",
                "convertImage.pdf", "resizeImage", "pinImage", "copyPath", "airDrop", "moveTo", "copyTo"
            ],
            "SVG offers every raster format, Resize and Pin, but no pixel tools")
        expect(tools("logo.svg").first?.options == [.scale(1), .scale(2), .scale(4)], "SVG conversion has a Scale option")
        expect(tools("logo.svg").first?.slot?.defaultOption == .scale(2), "SVG scale defaults to 2×")
        expect(tools("a.png").first?.options.isEmpty == true, "raster conversion has no options")
        let undecodable = FileToolCatalog.Context(decodableImages: [], canPickFolders: true)
        expect(
            tools(["a.webp"], context: undecodable).map(\.id) == ["copyPath", "airDrop", "moveTo", "copyTo"],
            "a type ImageIO cannot read gets only the file actions")
        let resize = tools("a.webp").first { $0.kind == .resizeImage }
        expect(resize?.target == .image(.png), "an image macOS cannot write is resized to PNG")
        expect(
            tools("a.heic").first { $0.kind == .compressImage }?.target == .image(.heic),
            "Compress keeps the source format")
        expect(
            tools("a.png").first { $0.kind == .compressImageToSize }?.target == .image(.jpeg),
            "a lossless source compresses to a size as JPEG")
        expect(
            tools("a.heic").first { $0.target == .image(.jpeg) }?.searchText.contains("jpg") == true,
            "a format's file extension finds its Convert row")
    }

    static func otherCatalog() {
        expect(
            ids("doc.pdf") == [
                "pdfToImages", "pdfToText", "splitPDF", "extractPages", "compressPDF", "copyText", "copyPath",
                "airDrop", "moveTo", "copyTo"
            ],
            "a PDF gets the PDF tools, not the image tools")
        expect(
            ids("song.mp3") == [
                "convertAudio.m4a", "convertAudio.wav", "convertAudio.aiff", "convertAudio.flac", "trimAudio",
                "copyPath", "airDrop", "moveTo", "copyTo"
            ],
            "MP3 converts to every audio format and trims")
        expect(!ids("song.wav").contains("convertAudio.wav"), "audio is never converted to its own format")
        expect(ids("song.m4a").contains("convertAudio.m4a"), "M4A converts to M4A to change the codec")
        expect(
            tools("song.mp3").first { $0.target == .audio(.m4a) }?.options == [.codec(.aac), .codec(.alac)],
            "M4A has a codec option")
        expect(
            ids("clip.mov") == ["changeSpeed", "changeSpeedAndPitch", "copyPath", "airDrop", "moveTo", "copyTo"],
            "a movie gets the two speed tools")
        expect(
            ids("clip.mkv") == ["copyPath", "airDrop", "moveTo", "copyTo"],
            "a container AVFoundation cannot export has no tools")
        expect(ids("notes.txt") == ["copyPath", "airDrop", "moveTo", "copyTo"], "a text file gets only the file actions")
        expect(ids("pack.zip").contains("extract"), "a ZIP extracts")
        expect(ids("pack.tar.gz").contains("extract"), "a TAR.GZ extracts")
        expect(ids("notes.txt.gz").contains("extract"), "a GZIP extracts")
        expect(!ids("pack.zip").contains("zip"), "archiving needs the Finder selection")
        let folder = FileToolsSubject(items: [item("Photos", directory: true)], origin: .search)
        expect(
            FileToolCatalog.tools(for: folder, context: context).map(\.id) == ["copyPath", "airDrop", "moveTo", "copyTo"],
            "a folder from File Search gets the file actions")
        let noSearch = FileToolCatalog.Context(decodableImages: [], canPickFolders: false)
        expect(
            tools(["notes.txt"], context: noSearch).map(\.id) == ["copyPath", "airDrop"],
            "Move and Copy need File Search to pick the folder")
    }

    static func finderCatalog() {
        let photos = ids(["a.heic", "b.jpg"], origin: .finder)
        expect(photos.contains("convertImage.png"), "a batch keeps a tool every file has")
        expect(!photos.contains("convertImage.jpeg"), "a batch drops a tool one file lacks")
        expect(photos.contains("imagesToPDF"), "images from Finder combine into a PDF")
        expect(photos.contains("zip") && photos.contains("tarGzip"), "a Finder selection archives")
        expect(!ids(["a.heic", "b.jpg"], origin: .search).contains("imagesToPDF"), "only Finder combines images")
        let pdfs = ids(["a.pdf", "b.pdf"], origin: .finder)
        expect(pdfs.contains("combinePDFs"), "PDFs from Finder combine")
        expect(!pdfs.contains("imagesToPDF"), "a PDF is not an image to combine")
        let mixed = ids(["a.pdf", "b.mp3"], origin: .finder)
        expect(
            mixed == ["zip", "tarGzip", "copyPath", "airDrop", "moveTo", "copyTo"],
            "a mixed selection keeps only what fits every file")
        expect(ids(["a.txt"], origin: .finder).contains("zip"), "a one-item Finder selection archives too")
        let folder = FileToolsSubject(items: [item("Photos", directory: true)], origin: .finder)
        expect(FileToolCatalog.tools(for: folder, context: context).map(\.id).contains("zip"), "a Finder folder zips")
    }

    static func options() {
        let compress = tools("a.jpg").first { $0.kind == .compressImage }!
        expect(compress.slot?.defaultOption == .quality(.medium), "Compress defaults to Medium")
        expect(compress.option(after: nil, backwards: false) == .quality(.medium), "Tab from nothing starts at Medium")
        expect(
            compress.option(after: .quality(.small), backwards: false) == .quality(.high),
            "Tab wraps from the last option to the first")
        expect(
            compress.option(after: .quality(.high), backwards: true) == .quality(.small),
            "⇧Tab wraps from the first option to the last")
        let strip = tools("a.jpg").first { $0.kind == .stripMetadata }!
        expect(strip.option(after: nil, backwards: false) == nil, "a tool without options has nothing to cycle")
        for slot in FileToolOptionSlot.allCases {
            for option in slot.choices {
                expect(FileToolOption(token: option.token) == option, "\(option.token) survives settings")
                expect(option.slot == slot, "\(option.token) names its own kind")
            }
        }
        expect(FileToolOption(token: "quality.huge") == nil, "an unknown token is dropped")
        expect(FileToolOption(token: "longestEdge.123") == nil, "an edge outside the list is dropped")
        expect(FileToolOption(token: "") == nil, "an empty token is dropped")
    }

    static func fields() {
        expect(FileToolFieldParser.pages("1-3, 5") == [1, 2, 3, 5], "pages read ranges and singles")
        expect(FileToolFieldParser.pages("5,1,3-4,1") == [1, 3, 4, 5], "pages sort and drop repeats")
        expect(FileToolFieldParser.pages("0") == nil, "page numbers start at 1")
        expect(FileToolFieldParser.pages("3-1") == nil, "a backwards range is refused")
        expect(FileToolFieldParser.pages("a") == nil, "words are refused")
        expect(FileToolFieldParser.pages("") == nil, "an empty page list is refused")
        expect(FileToolFieldParser.label(for: [1, 2, 3, 5, 7, 8]) == "1-3,5,7-8", "the page label folds runs")
        expect(FileToolFieldParser.seconds("90") == 90, "a time reads plain seconds")
        expect(FileToolFieldParser.seconds("1:30") == 90, "a time reads minutes and seconds")
        expect(FileToolFieldParser.seconds("1:00:05.5") == 3605.5, "a time reads hours")
        expect(FileToolFieldParser.seconds("1:75") == nil, "seconds past 59 are refused")
        expect(FileToolFieldParser.seconds("-3") == nil, "a negative time is refused")
        expect(FileToolFieldParser.bytes("500 KB") == 500_000, "a size reads KB")
        expect(FileToolFieldParser.bytes("2mb") == 2_000_000, "a size reads MB without a space")
        expect(FileToolFieldParser.bytes("1.5 MB") == 1_500_000, "a size reads a fraction")
        expect(FileToolFieldParser.bytes("300") == 300_000, "a bare number is KB")
        expect(FileToolFieldParser.bytes("0.5 KB") == nil, "a size under 1 KB is refused")
        expect(FileToolFieldParser.sizeLabel(2_000_000) == "2 MB", "a size label prefers whole MB")
        expect(FileToolFieldParser.sizeLabel(1_500_000) == "1.5 MB", "a size label shows a fractional MB")
        expect(FileToolFieldParser.sizeLabel(500_000) == "500 KB", "a size label falls back to KB")

        let trim: [FileToolField] = [.start, .end]
        if case .failure(let error) = FileToolFieldParser.parameters(for: trim, values: [:]) {
            expect(error == .emptyTrim, "an empty trim names the problem")
        } else {
            expect(false, "an empty trim is refused")
        }
        let end = try? FileToolFieldParser.parameters(for: trim, values: [.end: "0:30"]).get()
        expect(end?.start == nil && end?.end == 30, "a trim with only an end keeps the start")
        if case .failure(let error) = FileToolFieldParser.parameters(for: trim, values: [.start: "10", .end: "5"]) {
            expect(error == .emptyTrim, "an end before the start is refused")
        } else {
            expect(false, "an end before the start is refused")
        }
        let pages = try? FileToolFieldParser.parameters(for: [.pages], values: [.pages: "2-4"]).get()
        expect(pages?.pages == [2, 3, 4] && pages?.pagesLabel == "2-4", "Extract Pages reads its field")
        expect(FileToolField.pages.isOptional == false && FileToolField.start.isOptional, "only trim fields are optional")
    }

    static func outputNames() {
        let source = URL(fileURLWithPath: "/Users/tester/Pictures/IMG_2041.HEIC")
        let png = tools("IMG_2041.HEIC").first { $0.target == .image(.png) && $0.kind == .convertImage }!
        let free = FileToolOutputName.destination(for: png, option: nil, sources: [source]) { _ in false }
        expect(free?.path == "/Users/tester/Pictures/IMG_2041.png", "a conversion keeps the name beside the original")

        var taken: Set<String> = ["/Users/tester/Pictures/IMG_2041.png", "/Users/tester/Pictures/IMG_2041 2.png"]
        let next = FileToolOutputName.destination(for: png, option: nil, sources: [source]) { taken.contains($0.path) }
        expect(next?.lastPathComponent == "IMG_2041 3.png", "a taken name counts up from 2")

        let resize = tools("a.heic").first { $0.kind == .resizeImage }!
        let resized = FileToolOutputName.destination(for: resize, option: .longestEdge(1280), sources: [source]) { _ in
            false
        }
        expect(resized?.lastPathComponent == "IMG_2041 1280px.heic", "Resize names the edge")

        let compress = tools("a.heic").first { $0.kind == .compressImage }!
        taken = ["/Users/tester/Pictures/IMG_2041 compressed.heic"]
        let compressed = FileToolOutputName.destination(
            for: compress, option: .quality(.small), sources: [source]
        ) { taken.contains($0.path) }
        expect(compressed?.lastPathComponent == "IMG_2041 compressed 2.heic", "Compress never reuses the original name")

        let sized = tools("a.heic").first { $0.kind == .compressImageToSize }!
        var parameters = FileToolParameters()
        parameters.sizeLabel = "500 KB"
        expect(
            FileToolOutputName.destination(for: sized, option: nil, parameters: parameters, sources: [source]) { _ in
                false
            }?.lastPathComponent == "IMG_2041 500 KB.heic",
            "Compress to Size names the size")

        let strip = tools("a.heic").first { $0.kind == .stripMetadata }!
        let stripped = FileToolOutputName.destination(for: strip, option: nil, sources: [source]) { _ in false }
        expect(stripped != source, "Strip Metadata never writes over the original")

        let dotted = URL(fileURLWithPath: "/tmp/v1.2 final.jpeg")
        let dottedPNG = tools("a.jpeg").first { $0.target == .image(.png) }!
        expect(
            FileToolOutputName.destination(for: dottedPNG, option: nil, sources: [dotted]) { _ in false }?
                .lastPathComponent == "v1.2 final.png",
            "only the last extension is replaced")

        let clip = URL(fileURLWithPath: "/tmp/clip.mov")
        let speed = tools("clip.mov").first { $0.kind == .changeSpeed }!
        expect(
            FileToolOutputName.destination(for: speed, option: .speed(.double), sources: [clip]) { _ in false }?
                .lastPathComponent == "clip 2×.mov",
            "Change Speed names the speed and keeps the container")

        let song = URL(fileURLWithPath: "/tmp/song.mp3")
        let trim = tools("song.mp3").first { $0.kind == .trimAudio }!
        expect(
            FileToolOutputName.destination(for: trim, option: nil, sources: [song]) { _ in false }?.lastPathComponent
                == "song trimmed.m4a",
            "a trimmed MP3 becomes M4A")
        let wave = URL(fileURLWithPath: "/tmp/take.wav")
        expect(
            FileToolOutputName.destination(for: trim, option: nil, sources: [wave]) { _ in false }?.lastPathComponent
                == "take trimmed.wav",
            "a trimmed WAV stays WAV")

        let pdf = URL(fileURLWithPath: "/tmp/report.pdf")
        let split = tools("report.pdf").first { $0.kind == .splitPDF }!
        expect(
            FileToolOutputName.destination(for: split, option: nil, sources: [pdf]) { _ in false }?.lastPathComponent
                == "report pages",
            "Split PDF writes a folder")
        let images = tools("report.pdf").first { $0.kind == .pdfToImages }!
        expect(images.output(for: pdf) == .folder, "PDF to Images writes a folder")

        let zip = tools(["a.txt", "b.txt"], origin: .finder).first { $0.kind == .zip }!
        let pair = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
        expect(
            FileToolOutputName.destination(for: zip, option: nil, sources: pair) { _ in false }?.lastPathComponent
                == "Archive.zip",
            "several items zip into Archive.zip")
        expect(
            FileToolOutputName.destination(for: zip, option: nil, sources: [pair[0]]) { _ in false }?
                .lastPathComponent == "a.txt.zip",
            "one item zips under its own name")
        let tgz = tools(["a.txt"], origin: .finder).first { $0.kind == .tarGzip }!
        expect(
            FileToolOutputName.destination(for: tgz, option: nil, sources: [pair[0]]) { _ in false }?
                .lastPathComponent == "a.txt.tar.gz",
            "TAR.GZ keeps its double extension")

        let extract = tools("pack.tar.gz").first { $0.kind == .extract }!
        let pack = URL(fileURLWithPath: "/tmp/pack.tar.gz")
        expect(
            FileToolOutputName.destination(for: extract, option: nil, sources: [pack]) { _ in false }?
                .lastPathComponent == "pack",
            "Extract names the folder after the archive")
        let gzip = URL(fileURLWithPath: "/tmp/notes.txt.gz")
        expect(
            FileToolOutputName.destination(for: extract, option: nil, sources: [gzip]) { _ in false }?
                .lastPathComponent == "notes.txt",
            "a GZIP extracts to the file inside")

        let qr = tools("a.png").first { $0.kind == .readQRCode }!
        expect(
            FileToolOutputName.destination(for: qr, option: nil, sources: [source]) { _ in false } == nil,
            "a text result has no output file")
    }

    static func requests() {
        let source = URL(fileURLWithPath: "/tmp/a.jpg")
        let destination = URL(fileURLWithPath: "/tmp/a compressed.jpg")
        let compress = tools("a.jpg").first { $0.kind == .compressImage }!
        let empty = FileToolParameters()
        expect(
            compress.request(option: nil, parameters: empty, sources: [source], destination: destination).option
                == .quality(.medium),
            "a request without a choice uses the default option")
        expect(
            compress.request(option: .longestEdge(640), parameters: empty, sources: [source], destination: destination)
                .option == .quality(.medium),
            "a request never carries an option of another tool")
        let request = compress.request(
            option: .quality(.high), parameters: empty, sources: [source], destination: destination)
        let decoded = try? JSONDecoder().decode(FileToolRequest.self, from: JSONEncoder().encode(request))
        expect(decoded == request, "a request survives the trip to the helper")
        expect(request.imageFormat == .jpeg && request.audioFormat == nil, "a request names its output format")
        let staged = request.staged(at: URL(fileURLWithPath: "/tmp/staging/a.jpg"))
        expect(
            staged.destination.path == "/tmp/staging/a.jpg" && staged.sources == request.sources,
            "staging moves only the destination")
    }

    static func archives() {
        expect(FileToolArchive(fileName: "a.ZIP") == .zip, "ZIP is found in any case")
        expect(FileToolArchive(fileName: "a.tgz") == .tarGzip, "TGZ is TAR.GZ")
        expect(FileToolArchive(fileName: "a.tar.bz2") == .tar, "TAR.BZ2 extracts as TAR")
        expect(FileToolArchive(fileName: "a.gz") == .gzip, "GZ alone is GZIP")
        expect(FileToolArchive(fileName: ".zip") == nil, "a bare extension is not an archive")
        expect(FileToolArchive(fileName: "a.rar") == nil, "RAR is not offered")
        expect(FileToolArchive.baseName(of: "Pack.Tar.Gz") == "Pack", "the base name drops the whole suffix")
    }

    static func finderTab() {
        let tab = FinderTabPolicy.tabKeyCode
        let list = FinderFocus(role: "AXOutline", subrole: nil, selectionCount: 2)
        expect(FinderTabPolicy.opensFileTools(keyCode: tab, flags: 0, focus: list), "Tab on a list selection opens")
        expect(
            FinderTabPolicy.opensFileTools(
                keyCode: tab, flags: 0, focus: FinderFocus(role: "AXGroup", subrole: nil, selectionCount: 1)),
            "Tab on an icon view selection opens")
        expect(
            !FinderTabPolicy.opensFileTools(
                keyCode: tab, flags: 0, focus: FinderFocus(role: "AXGroup", subrole: nil, selectionCount: 0)),
            "Tab with nothing selected passes")
        expect(
            !FinderTabPolicy.opensFileTools(
                keyCode: tab, flags: 0, focus: FinderFocus(role: "AXGroup", subrole: nil, selectionCount: nil)),
            "Tab passes when the selection cannot be read")
        expect(
            !FinderTabPolicy.opensFileTools(
                keyCode: tab, flags: 0, focus: FinderFocus(role: "AXTextField", subrole: nil, selectionCount: 1)),
            "Tab in a rename field passes")
        expect(
            !FinderTabPolicy.opensFileTools(
                keyCode: tab, flags: 0, focus: FinderFocus(role: "AXTextField", subrole: "AXSearchField", selectionCount: 1)),
            "Tab in the search field passes")
        expect(
            !FinderTabPolicy.opensFileTools(
                keyCode: tab, flags: 0, focus: FinderFocus(role: "AXButton", subrole: nil, selectionCount: 1)),
            "Tab on a button passes")
        expect(!FinderTabPolicy.opensFileTools(keyCode: tab, flags: 0, focus: nil), "a failed read passes")
        expect(
            !FinderTabPolicy.opensFileTools(keyCode: tab, flags: 0x0002_0000, focus: list), "⇧Tab keeps its Finder meaning")
        expect(!FinderTabPolicy.opensFileTools(keyCode: tab, flags: 0x0010_0000, focus: list), "⌘Tab passes")
        expect(!FinderTabPolicy.opensFileTools(keyCode: 36, flags: 0, focus: list), "another key passes")
        expect(FinderTabPolicy.isCandidate(keyCode: tab, flags: 0x100), "a device flag does not hide a bare Tab")
    }
}
