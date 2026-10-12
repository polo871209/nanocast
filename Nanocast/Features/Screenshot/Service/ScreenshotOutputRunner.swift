import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ScreenshotOutputRunner {
    @concurrent
    static func png(of image: CGImage, scale: CGFloat) async -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let density = 72 * scale
        let properties = [kCGImagePropertyDPIWidth: density, kCGImagePropertyDPIHeight: density] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    @concurrent
    static func temporaryPNG(of image: CGImage) async -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "Nanocast-OCR-\(UUID().uuidString).png", directoryHint: .notDirectory)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    @MainActor
    static func copy(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    @MainActor
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @concurrent
    static func save(_ png: Data, in folder: URL, at date: Date) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = freeURL(for: .screenshot, in: folder, at: date)
        try png.write(to: url, options: .withoutOverwriting)
        return url
    }

    @concurrent
    static func recordingURL(in folder: URL, at date: Date, as format: ScreenRecordingFormat) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return freeURL(for: .recording(format), in: folder, at: date)
    }

    private static func freeURL(for kind: ScreenshotFileName.Kind, in folder: URL, at date: Date) -> URL {
        let name = ScreenshotFileName.name(of: kind, at: date, in: .current) { candidate in
            FileManager.default.fileExists(atPath: folder.appending(path: candidate, directoryHint: .notDirectory).path)
        }
        return folder.appending(path: name, directoryHint: .notDirectory)
    }
}
