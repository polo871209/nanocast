import CoreGraphics
import Foundation
import Synchronization

final class ScrollStitchFile: Sendable {
    private let url: URL
    private let width: Int
    private let handle: Mutex<FileHandle?>

    init?(width: Int) {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "Nanocast-scroll-\(UUID().uuidString).bgra", directoryHint: .notDirectory)
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
            let handle = try? FileHandle(forUpdating: url)
        else { return nil }
        self.url = url
        self.width = width
        self.handle = Mutex(handle)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ step: ScrollStitch.Step, of frame: ScrollFrame) -> Bool {
        guard frame.width == width else { return false }
        return handle.withLock { handle in
            guard let handle else { return false }
            switch step {
            case .started(let rows):
                return append(rows, of: frame, to: handle)
            case .extended(let keep, let rows):
                guard (try? handle.truncate(atOffset: UInt64(keep * width * 4))) != nil else { return false }
                return append(rows, of: frame, to: handle)
            case .unchanged, .lost, .full:
                return true
            }
        }
    }

    func image(height: Int, space: CGColorSpace) -> CGImage? {
        handle.withLock { handle in
            try? handle?.close()
            handle = nil
        }
        defer { try? FileManager.default.removeItem(at: url) }
        guard height > 0, let data = try? Data(contentsOf: url, options: .alwaysMapped),
            data.count == height * width * 4, let provider = CGDataProvider(data: data as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
            bitmapInfo: ScrollFrame.bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
    }

    private func append(_ rows: Range<Int>, of frame: ScrollFrame, to handle: FileHandle) -> Bool {
        let bytes = frame.pixels[(rows.lowerBound * frame.bytesPerRow)..<(rows.upperBound * frame.bytesPerRow)]
        return (try? handle.seekToEnd()) != nil && (try? handle.write(contentsOf: bytes)) != nil
    }
}
