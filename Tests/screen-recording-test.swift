import AVFoundation
import AppKit
import ScreenCaptureKit

@main
@MainActor
struct ScreenRecordingTests {
    static var failures = 0
    static let folder = FileManager.default.temporaryDirectory.appending(
        path: "nanocast-recording-\(UUID().uuidString)", directoryHint: .isDirectory)

    static func main() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            print("SKIP: this process has no Screen Recording grant")
            return
        }
        guard try await !SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays.isEmpty
        else {
            print("SKIP: no display can be captured, for example while the screen is locked")
            return
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let full = try await record("full", stoppingAfter: .seconds(1))
        expect(full.ended, "a one-second recording ends after stop")
        expect(
            full.duration > full.recordedFor - 0.1,
            "a recording keeps its length, got \(full.duration)s of \(full.recordedFor)s")

        let sound = try await record(
            "system-audio", stoppingAfter: .seconds(1),
            options: ScreenRecordingOptions(capturesSystemAudio: true, showsClicks: true))
        expect(sound.ended, "a recording with system audio and clicks ends after stop")
        expect(sound.audioTracks == 1, "system audio lands in one audio track, got \(sound.audioTracks)")
        expect(full.audioTracks == 0, "a recording without audio has no audio track, got \(full.audioTracks)")

        let onStart = try await record("on-start", stoppingOnStart: true)
        expect(onStart.ended, "a stop the moment recording starts still ends it")
        expect(onStart.duration > 0, "a stop the moment recording starts still saves a playable file")

        let marker = panel(at: CGRect(x: 40, y: 40, width: 80, height: 80), .red, level: .screenSaver)
        try await Task.sleep(for: .milliseconds(300))
        let shown = try await record(
            "own-window-shown", stoppingAfter: .seconds(1), showing: [CGWindowID(marker.windowNumber)])
        let hidden = try await record("own-window-hidden", stoppingAfter: .seconds(1))
        expect(shown.isRed(at: markerCenter), "a window the caller names is recorded while the process is left out")
        expect(!hidden.isRed(at: markerCenter), "the process's other windows stay out of the recording")

        let target = panel(at: recordedRect, .blue, level: .floating)
        let cover = panel(at: CGRect(x: 200, y: 40, width: 80, height: 80), .yellow, level: .screenSaver)
        try await Task.sleep(for: .milliseconds(300))
        let inPlace = try await record(
            "window-in-place", stoppingAfter: .seconds(1), showing: [CGWindowID(marker.windowNumber)],
            window: CGWindowID(target.windowNumber))
        for panel in [marker, target, cover] { panel.orderOut(nil) }
        expect(inPlace.isRed(at: markerCenter), "a window recorded in place keeps the windows the caller names")
        expect(
            inPlace.isBlue(at: CGPoint(x: 240, y: 80)), "a window recorded in place leaves out a window above it")

        let delays = Array(stride(from: 0, through: 300, by: 20)) + Array(stride(from: 30, through: 60, by: 2))
        for delay in delays {
            let result = try await record("after-\(delay)", stoppingAfter: .milliseconds(delay))
            expect(result.ended, "a stop \(delay) ms after the start ends the recording")
            expect(
                result.cancelled || result.duration > 0,
                "a stop \(delay) ms after the start either cancels or saves a playable file")
        }
        exit(failures == 0 ? 0 : 1)
    }

    struct Outcome {
        var ended = false
        var cancelled = false
        var duration = 0.0
        var recordedFor = 0.0
        var audioTracks = 0
        var frame: CGImage?

        func isRed(at point: CGPoint) -> Bool {
            guard let pixel = color(at: point) else { return false }
            return pixel[0] > 200 && pixel[1] < 60 && pixel[2] < 60
        }

        func isBlue(at point: CGPoint) -> Bool {
            guard let pixel = color(at: point) else { return false }
            return pixel[0] < 60 && pixel[1] < 60 && pixel[2] > 200
        }

        private func color(at point: CGPoint) -> [UInt8]? {
            guard let frame else { return nil }
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let width = Double(frame.width)
            let height = Double(frame.height)
            let x = point.x / recordedRect.width
            let y = point.y / recordedRect.height
            context.draw(frame, in: CGRect(x: -x * width, y: -(1 - y) * height, width: width, height: height))
            return pixel
        }
    }

    nonisolated static let recordedRect = CGRect(x: 0, y: 0, width: 320, height: 200)
    static let markerCenter = CGPoint(x: 80, y: 80)

    static func record(
        _ name: String, stoppingAfter delay: Duration = .zero, stoppingOnStart: Bool = false,
        options: ScreenRecordingOptions = ScreenRecordingOptions(), showing ownWindows: [CGWindowID] = [],
        window: CGWindowID? = nil
    ) async throws -> Outcome {
        let display = CGMainDisplayID()
        let source: ScreenRecordingRunner.Source =
            if let window {
                .windowInPlace(id: window, display: display, rect: recordedRect, pixelWidth: 640, pixelHeight: 400)
            } else {
                .area(display: display, rect: recordedRect, pixelWidth: 640, pixelHeight: 400)
            }
        let url = folder.appending(path: "\(name).mov", directoryHint: .notDirectory)
        weak var stoppable: ScreenRecordingRunner?
        var startedAt: ContinuousClock.Instant?
        let runner = ScreenRecordingRunner {
            startedAt = .now
            if stoppingOnStart { stoppable?.stop() }
        }
        stoppable = runner
        var result = Outcome()
        let recording = Task {
            do {
                try await runner.record(source, with: options, showing: ownWindows, to: url, as: .mov)
            } catch is CancellationError {
                result.cancelled = true
            }
            result.ended = true
        }
        if !stoppingOnStart {
            try await Task.sleep(for: delay)
            runner.stop()
            if let startedAt {
                let elapsed = startedAt.duration(to: .now).components
                result.recordedFor = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            }
        }
        for _ in 0..<150 where !result.ended {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard result.ended else {
            recording.cancel()
            return result
        }
        try await recording.value
        if !result.cancelled {
            let asset = AVURLAsset(url: url)
            result.duration = try await asset.load(.duration).seconds
            result.audioTracks = try await asset.loadTracks(withMediaType: .audio).count
            result.frame = try await AVAssetImageGenerator(asset: asset)
                .image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        }
        return result
    }

    static func panel(at rect: CGRect, _ color: NSColor, level: NSWindow.Level) -> NSPanel {
        let screen = NSScreen.screens.first { $0.frame.origin == .zero }!
        let panel = NSPanel(
            contentRect: CGRect(
                x: rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = level
        panel.backgroundColor = color.usingColorSpace(.sRGB)
        panel.orderFrontRegardless()
        panel.display()
        return panel
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}
