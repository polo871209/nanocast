import AppKit
import SwiftUI

@MainActor
final class ScreenRecordingController {
    enum Outcome {
        case saved(URL)
        case discarded
        case failed(any Error)
    }

    private let session: ScreenRecordingSession
    private let source: ScreenRecordingRunner.Source
    private let options: ScreenRecordingOptions
    private let border: LiveCapturePanel?
    private let camera: RecordingCamera?
    private let bubble: CameraBubble?
    private let bar: LiveCapturePanel
    private var runner: ScreenRecordingRunner?
    private let segmentsFolder = FileManager.default.temporaryDirectory.appending(
        path: "Screen Recording \(UUID().uuidString)", directoryHint: .isDirectory)
    private var segments: [URL] = []
    private var recorded: TimeInterval = 0
    private var keepsFile = true
    private var failure: (any Error)?
    private var work: Task<Void, Never>?
    private let folder: URL
    private let format: ScreenRecordingFormat
    private let finish: (Outcome) -> Void

    init(
        _ source: ScreenRecordingRunner.Source, with options: ScreenRecordingOptions, camera: RecordingCamera?,
        area points: CGRect, on display: CapturedDisplay, showsBorder: Bool, savingIn folder: URL,
        as format: ScreenRecordingFormat, metrics: InterfaceMetrics, finish: @escaping (Outcome) -> Void
    ) {
        session = ScreenRecordingSession(status: .ready)
        self.folder = folder
        self.format = format
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
                session: session, metrics: chrome, record: { controller?.resume() },
                pause: { controller?.pause() }, stop: { controller?.stop(keeping: true) },
                discard: { controller?.stop(keeping: false) }))
        bar = LiveCapturePanel(
            frame: global(
                ChromePlacement.toolbar(
                    size: content.fittingSize, area: points, in: CGRect(origin: .zero, size: display.frame.size),
                    gap: Theme.Spacing.md)))
        bar.contentView = content
        controller = self
    }

    func start() {
        border?.orderFrontRegardless()
        bar.orderFrontRegardless()
        bubble?.show()
        if camera == nil { resume() }
    }

    func recordOrStop() {
        if session.status == .ready { resume() } else { stop(keeping: true) }
    }

    func stopAndWait() async {
        stop(keeping: true)
        await work?.value
    }

    private func resume() {
        switch session.status {
        case .ready, .paused: break
        case .starting, .recording, .saving: return
        }
        session.status = .starting
        enqueue { [self] in await recordSegment() }
    }

    private func pause() {
        guard wantsRecording else { return }
        if case .recording(let since) = session.status { recorded = Date.now.timeIntervalSince(since) }
        session.status = .paused(recorded: recorded)
        runner?.stop()
    }

    func stop(keeping: Bool) {
        guard session.status != .saving else { return }
        keepsFile = keeping
        session.status = .saving
        runner?.stop()
        enqueue { [self] in await end() }
    }

    private var wantsRecording: Bool {
        switch session.status {
        case .starting, .recording: true
        case .ready, .paused, .saving: false
        }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = work
        work = Task {
            await previous?.value
            await operation()
        }
    }

    private func segmentStarted() {
        guard wantsRecording else { return }
        session.status = .recording(since: Date.now.addingTimeInterval(-recorded))
    }

    private func recordSegment() async {
        guard wantsRecording, failure == nil else { return }
        let url = segmentsFolder.appending(path: "\(segments.count).\(format.fileExtension)", directoryHint: .notDirectory)
        let runner = ScreenRecordingRunner { [weak self] in self?.segmentStarted() }
        self.runner = runner
        defer { self.runner = nil }
        do {
            try FileManager.default.createDirectory(at: segmentsFolder, withIntermediateDirectories: true)
            try await runner.record(
                source, with: options, showing: [bubble?.windowID].compactMap(\.self), to: url, as: format)
            segments.append(url)
            let stoppedOutsideNanocast = wantsRecording
            if stoppedOutsideNanocast { stop(keeping: true) }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: url)
        } catch {
            failure = error
            stop(keeping: true)
        }
    }

    private func end() async {
        let outcome = await save()
        try? FileManager.default.removeItem(at: segmentsFolder)
        for panel in [border, bar].compactMap(\.self) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        bubble?.close()
        camera?.stop()
        finish(outcome)
    }

    private func save() async -> Outcome {
        guard keepsFile else { return .discarded }
        guard !segments.isEmpty else { return failure.map(Outcome.failed) ?? .discarded }
        do {
            let url = try await Self.newFile(in: folder, as: format)
            try await RecordingJoinService.join(segments, into: url, as: format)
            return .saved(url)
        } catch {
            return .failed(error)
        }
    }

    @concurrent
    private static func newFile(in folder: URL, as format: ScreenRecordingFormat) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return TimestampedFileName.freeURL("Screen Recording", extension: format.fileExtension, in: folder, at: .now)
    }
}
