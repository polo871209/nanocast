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
    private let border: LiveCapturePanel?
    private let bar: LiveCapturePanel
    private var runner: ScreenRecordingRunner?
    private var url: URL?
    private var keepsFile = true
    private let finish: (Outcome) -> Void

    init(
        _ source: ScreenRecordingRunner.Source, area points: CGRect, on display: CapturedDisplay, showsBorder: Bool,
        metrics: InterfaceMetrics, finish: @escaping (Outcome) -> Void
    ) {
        self.source = source
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
        let runner = ScreenRecordingRunner(
            started: { [weak self] in self?.session.status = .recording(since: .now) },
            ended: { [weak self] in self?.ended($0) })
        self.runner = runner
        Task { [weak self, source] in
            do {
                let url = try await ScreenshotOutputRunner.recordingURL(in: folder, at: .now, as: format)
                self?.url = url
                await runner.start(source, writingTo: url, as: format)
            } catch {
                self?.ended(.failure(error))
            }
        }
    }

    func stop(keeping: Bool) {
        guard session.status != .saving else { return }
        keepsFile = keeping
        session.status = .saving
        runner?.stop()
    }

    private func ended(_ result: Result<Void, any Error>) {
        guard runner != nil else { return }
        runner = nil
        for panel in [border, bar].compactMap(\.self) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        if case .success = result, keepsFile, let url { return finish(.saved(url)) }
        if let url { try? FileManager.default.removeItem(at: url) }
        switch result {
        case .failure(let error) where keepsFile && !(error is CancellationError):
            finish(.failed(error))
        default:
            finish(.discarded)
        }
    }
}
