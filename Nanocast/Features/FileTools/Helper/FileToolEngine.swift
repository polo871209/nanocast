import Foundation

nonisolated enum FileToolEngine {
    enum Failure: Error {
        case unreadable
        case unwritable
        case unsupported
        case tool(Int32)
    }

    static func run(_ request: FileToolRequest) async throws {
        switch request.kind {
        case .convertImage, .compressImage, .compressImageToSize, .resizeImage, .stripMetadata:
            try FileToolImageEngine.run(request)
        case .readQRCode:
            try await FileToolCodeEngine.run(request)
        case .zip, .tarGzip, .extract:
            try FileToolArchiveEngine.run(request)
        case .changeSpeed, .changeSpeedAndPitch, .convertAudio, .trimAudio:
            try await FileToolMediaEngine.run(request)
        case .combinePDFs, .imagesToPDF, .splitPDF, .extractPages, .compressPDF, .pdfToImages, .pdfToText:
            try FileToolPDFEngine.run(request)
        case .copyText, .pinImage, .copyPath, .airDrop, .moveTo, .copyTo:
            throw Failure.unsupported
        }
    }

    /// One line per update on standard output, read by `FileToolWorker`.
    static func report(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        FileHandle.standardOutput.write(Data("progress \(clamped)\n".utf8))
    }

    static func runTool(_ path: String, _ arguments: [String], in directory: URL? = nil, output: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ["COPYFILE_DISABLE": "1", "PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if let output {
            guard FileManager.default.createFile(atPath: output.path, contents: nil),
                let handle = try? FileHandle(forWritingTo: output)
            else { throw Failure.unwritable }
            process.standardOutput = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.tool(process.terminationStatus) }
    }
}
