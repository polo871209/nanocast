import AppKit
import SwiftUI

@MainActor
final class ScreenRecordingController {
    enum Outcome {
        case saved(URL)
        case discarded
        case failed(any Error)
    }

    private let session = ScreenRecordingSession()
    private let source: ScreenRecordingRunner.Source
    private let options: ScreenRecordingOptions
    private let border: LiveCapturePanel?
    private let camera: RecordingCamera?
    private let bubble: CameraBubble?
    private let bar: LiveCapturePanel
    private lazy var runner = ScreenRecordingRunner { [weak self] in self?.session.status = .recording(since: .now) }
    private var recording: Task<Void, Never>?
    private var keepsFile = true
    private let finish: (Outcome) -> Void

    init(
        _ source: ScreenRecordingRunner.Source, with options: ScreenRecordingOptions, camera: RecordingCamera?,
        area points: CGRect, on display: CapturedDisplay, showsBorder: Bool, metrics: InterfaceMetrics,
        finish: @escaping (Outcome) -> Void
    ) {
        self.source = source
        self.options = options
        self.camera = camera
        self.finish = finish
        func global(_ rect: CGRect) -> CGRect {
            CGRect(
                x: display.frame.minX + rect.minX, y: display.frame.maxY - rect.maxY, width: rect.width,
                height: rect.height)
        }
        if showsBorder {
            let outset = -Theme.Size.captureBorder
            let border = LiveCapturePanel(frame: global(points.insetBy(dx: outset, dy: outset)))
            border.ignoresMouseEvents = true
            border.contentView = LiveCapturePanel.borderView(color: Theme.Colors.destructive)
            self.border = border
        } else {
            border = nil
        }
        bubble = camera.map { CameraBubble(session: $0.session, inside: global(points)) }
        let chrome = InterfaceMetrics(scale: metrics.scale * Theme.Markup.chromeScale)
        weak var controller: ScreenRecordingController?
        let content = FirstMouseHostingView(
            rootView: ScreenRecordingView(
                session: session, metrics: chrome, stop: { controller?.stop(keeping: true) },
                discard: { controller?.stop(keeping: false) }))
        bar = LiveCapturePanel(
            frame: global(
                ChromePlacement.toolbar(
                    size: content.fittingSize, area: points, in: CGRect(origin: .zero, size: display.frame.size),
                    gap: Theme.Spacing.md)))
        bar.contentView = content
        controller = self
    }

    func start(savingIn folder: URL, as format: ScreenRecordingFormat) {
        border?.orderFrontRegardless()
        bar.orderFrontRegardless()
        bubble?.show()
        recording = Task {
            let outcome = await record(savingIn: folder, as: format)
            for panel in [border, bar].compactMap(\.self) {
                panel.orderOut(nil)
                panel.contentView = nil
            }
            bubble?.close()
            camera?.stop()
            finish(outcome)
        }
    }

    func stop(keeping: Bool) {
        guard session.status != .saving else { return }
        keepsFile = keeping
        session.status = .saving
        runner.stop()
    }

    func stopAndWait() async {
        stop(keeping: true)
        await recording?.value
    }

    private func record(savingIn folder: URL, as format: ScreenRecordingFormat) async -> Outcome {
        let url: URL
        do {
            url = try await Self.newFile(in: folder, as: format)
        } catch {
            return .failed(error)
        }
        do {
            try await runner.record(
                source, with: options, showing: [bubble?.windowID].compactMap(\.self), to: url, as: format)
            if keepsFile { return .saved(url) }
            try? FileManager.default.removeItem(at: url)
            return .discarded
        } catch {
            try? FileManager.default.removeItem(at: url)
            return keepsFile && !(error is CancellationError) ? .failed(error) : .discarded
        }
    }

    @concurrent
    private static func newFile(in folder: URL, as format: ScreenRecordingFormat) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return TimestampedFileName.freeURL("Screen Recording", extension: format.fileExtension, in: folder, at: .now)
    }
}
