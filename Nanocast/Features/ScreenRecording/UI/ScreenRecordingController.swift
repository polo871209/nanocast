import AppKit
import SwiftUI

@MainActor
final class ScreenRecordingController {
    enum Outcome {
        case saved(URL)
        case discarded
        case failed(any Error)
    }

    private struct Placement: Equatable {
        let display: CGDirectDisplayID
        let frame: CGRect
    }

    private static let windowSettleDelay: TimeInterval = 0.4

    private let session: ScreenRecordingSession
    private unowned let coordinator: ScreenRecordingCoordinator
    private let metrics: InterfaceMetrics
    private let border: LiveCapturePanel
    private let bar: LiveCapturePanel
    private var placement: Placement?
    private var camera: RecordingCamera?
    private var bubble: CameraBubble?
    private var sourcePicker: RecordingPickerPanel?
    private var tracking: Timer?
    private var windowMovedAt: Date?
    private var pixelSize: (width: Int, height: Int)?
    private var runner: ScreenRecordingRunner?
    private let segmentsFolder = FileManager.default.temporaryDirectory.appending(
        path: "Screen Recording \(UUID().uuidString)", directoryHint: .isDirectory)
    private var segments: [URL] = []
    private var keepsFile = true
    private var failure: (any Error)?
    private var work: Task<Void, Never>?

    init(target: RecordingTarget, coordinator: ScreenRecordingCoordinator, metrics: InterfaceMetrics) {
        session = ScreenRecordingSession(target: target)
        self.coordinator = coordinator
        self.metrics = metrics
        border = LiveCapturePanel(frame: .zero)
        border.ignoresMouseEvents = true
        border.contentView = LiveCapturePanel.borderView(color: Theme.Colors.destructive)
        let chrome = InterfaceMetrics(scale: metrics.scale * Theme.Markup.chromeScale)
        weak var controller: ScreenRecordingController?
        let content = FirstMouseHostingView(
            rootView: ScreenRecordingView(
                session: session, metrics: chrome,
                actions: .init(
                    choose: { controller?.choose($0) }, toggleMicrophone: { controller?.toggleMicrophone() },
                    toggleCamera: { controller?.toggleCamera() }, recordOrPause: { controller?.recordOrPause() },
                    stop: { controller?.stop(keeping: true) }, discard: { controller?.stop(keeping: false) })))
        bar = LiveCapturePanel(frame: CGRect(origin: .zero, size: content.fittingSize))
        bar.contentView = content
        controller = self
    }

    func start(microphone: Bool, camera: Bool) {
        apply(session.target)
        bar.orderFrontRegardless()
        if microphone { toggleMicrophone() }
        if camera { toggleCamera() }
        tracking = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackWindow() }
        }
    }

    func recordOrStop() {
        if session.status == .setup { recordOrPause() } else { stop(keeping: true) }
    }

    func stopAndWait() async {
        stop(keeping: session.status != .setup)
        await work?.value
    }

    private func choose(_ kind: RecordingTargetKind) {
        guard session.status == .setup else { return }
        switch kind {
        case .display:
            if let id = NSScreen.underCursor?.displayID { apply(.display(id)) }
        case .area:
            setChromeVisible(false)
            let isPicking = coordinator.pickArea { [weak self] target in
                guard let self else { return }
                setChromeVisible(true)
                if let target { apply(target) }
            }
            if !isPicking { setChromeVisible(true) }
        case .window:
            guard sourcePicker == nil, let screen = NSScreen.underCursor else { return }
            let picker = RecordingPickerPanel(on: screen, metrics: metrics) { [weak self] target in
                self?.sourcePicker = nil
                if let target { self?.apply(target) }
            }
            sourcePicker = picker
            picker.show()
        }
    }

    private func toggleMicrophone() {
        if session.microphone {
            session.microphone = false
            coordinator.remember(microphone: false)
            restartSegment()
            return
        }
        Task {
            guard await coordinator.allowsMicrophone(), !isSaving else { return }
            session.microphone = true
            coordinator.remember(microphone: true)
            restartSegment()
        }
    }

    private func toggleCamera() {
        guard !session.isChangingCamera else { return }
        if session.camera {
            bubble?.close()
            bubble = nil
            camera?.stop()
            camera = nil
            session.camera = false
            coordinator.remember(camera: false)
            restartSegment()
            return
        }
        session.isChangingCamera = true
        Task {
            let camera = await coordinator.startCamera()
            session.isChangingCamera = false
            guard let camera, !isSaving else {
                camera?.stop()
                return
            }
            self.camera = camera
            if let placement {
                let bubble = CameraBubble(session: camera.session, inside: Self.appKitFrame(placement.frame))
                bubble.show()
                self.bubble = bubble
            }
            session.camera = true
            coordinator.remember(camera: true)
            restartSegment()
        }
    }

    private func recordOrPause() {
        switch session.status {
        case .setup:
            guard let placement,
                let scale = NSScreen.screens.first(where: { $0.displayID == placement.display })?
                    .backingScaleFactor
            else { return }
            sourcePicker?.close()
            sourcePicker = nil
            pixelSize = (Int(placement.frame.width * scale) & ~1, Int(placement.frame.height * scale) & ~1)
            capture(from: 0)
        case .paused(let recorded):
            capture(from: recorded)
        case .starting(let recorded):
            session.status = .paused(recorded: recorded)
            runner?.stop()
        case .recording:
            session.status = .paused(recorded: session.recorded(at: .now))
            runner?.stop()
        case .saving:
            break
        }
    }

    private func stop(keeping: Bool) {
        guard !isSaving else { return }
        keepsFile = keeping
        session.status = .saving(recorded: session.recorded(at: .now))
        runner?.stop()
        sourcePicker?.close()
        sourcePicker = nil
        enqueue { [self] in await end() }
    }

    private var isSaving: Bool {
        if case .saving = session.status { true } else { false }
    }

    private func capture(from recorded: TimeInterval) {
        session.status = .starting(recorded: recorded)
        enqueue { [self] in await recordSegment() }
    }

    private func restartSegment() {
        guard session.isCapturing else { return }
        runner?.stop()
        capture(from: session.recorded(at: .now))
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = work
        work = Task {
            await previous?.value
            await operation()
        }
    }

    private func segmentStarted() {
        guard case .starting(let recorded) = session.status else { return }
        session.status = .recording(since: Date.now.addingTimeInterval(-recorded))
    }

    private func recordSegment() async {
        guard session.isCapturing, failure == nil, let source = currentSource() else { return }
        let url = segmentsFolder.appending(
            path: "\(segments.count).\(coordinator.format.fileExtension)", directoryHint: .notDirectory)
        let runner = ScreenRecordingRunner(
            started: { [weak self] in self?.segmentStarted() },
            heard: { [weak self] in self?.session.microphoneLevel = $0 })
        self.runner = runner
        defer {
            self.runner = nil
            session.microphoneLevel = 0
        }
        do {
            try FileManager.default.createDirectory(at: segmentsFolder, withIntermediateDirectories: true)
            try await runner.record(
                source, with: coordinator.options(microphone: session.microphone),
                showing: [bubble?.windowID].compactMap(\.self), to: url, as: coordinator.format)
            segments.append(url)
            let endedOutsideNanocast = !runner.isStopRequested
            if endedOutsideNanocast { stop(keeping: true) }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: url)
        } catch {
            failure = error
            stop(keeping: true)
        }
    }

    private func currentSource() -> ScreenRecordingRunner.Source? {
        guard let pixelSize, let placement = Self.resolve(session.target) ?? placement else { return nil }
        let bounds = CGDisplayBounds(placement.display)
        let local = placement.frame.intersection(bounds).offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        let (width, height) = pixelSize
        switch session.target {
        case .display, .area:
            return .area(display: placement.display, rect: local, pixelWidth: width, pixelHeight: height)
        case .window(let id) where bubble == nil:
            return .window(id: id, pixelWidth: width, pixelHeight: height)
        case .window(let id):
            return .windowInPlace(
                id: id, display: placement.display, rect: local, pixelWidth: width, pixelHeight: height)
        }
    }

    private func end() async {
        let outcome = await save()
        try? FileManager.default.removeItem(at: segmentsFolder)
        tracking?.invalidate()
        tracking = nil
        for panel in [border, bar] {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        bubble?.close()
        camera?.stop()
        coordinator.finish(outcome)
    }

    private func save() async -> Outcome {
        guard keepsFile else { return .discarded }
        guard !segments.isEmpty else { return failure.map(Outcome.failed) ?? .discarded }
        do {
            let url = try await Self.newFile(in: coordinator.saveFolder, as: coordinator.format)
            try await RecordingJoinService.join(segments, into: url, as: coordinator.format)
            return .saved(url)
        } catch {
            return .failed(error)
        }
    }

    private func apply(_ target: RecordingTarget) {
        guard let placement = Self.resolve(target) else { return }
        session.target = target
        move(to: placement)
        let bounds = CGDisplayBounds(placement.display)
        let size = bar.frame.size
        bar.setFrame(
            Self.appKitFrame(
                ChromePlacement.toolbar(size: size, area: placement.frame, in: bounds, gap: Theme.Spacing.md)),
            display: true)
    }

    private func move(to placement: Placement) {
        let previous = self.placement
        self.placement = placement
        if case .display = session.target {
            border.orderOut(nil)
        } else {
            let outset = -Theme.Size.captureBorder
            border.setFrame(Self.appKitFrame(placement.frame).insetBy(dx: outset, dy: outset), display: true)
            if !isSaving { border.orderFrontRegardless() }
        }
        if let previous {
            bubble?.follow(Self.appKitFrame(placement.frame), from: Self.appKitFrame(previous.frame))
        }
    }

    private func trackWindow() {
        guard case .window = session.target, !isSaving else { return }
        guard let current = Self.resolve(session.target) else { return windowClosed() }
        if current != placement {
            move(to: current)
            if bubble != nil, session.isCapturing { windowMovedAt = .now }
        } else if let movedAt = windowMovedAt, Date.now.timeIntervalSince(movedAt) > Self.windowSettleDelay {
            windowMovedAt = nil
            restartSegment()
        }
    }

    private func windowClosed() {
        if session.status == .setup, let id = placement?.display {
            apply(.display(id))
        } else {
            stop(keeping: true)
        }
    }

    private func setChromeVisible(_ isVisible: Bool) {
        if isVisible {
            bar.orderFrontRegardless()
            bubble?.show()
            if let placement { move(to: placement) }
        } else {
            for panel in [border, bar] { panel.orderOut(nil) }
            bubble?.hide()
        }
    }

    private static func resolve(_ target: RecordingTarget) -> Placement? {
        switch target {
        case .display(let id):
            return Placement(display: id, frame: CGDisplayBounds(id))
        case .area(let id, let rect):
            let bounds = CGDisplayBounds(id)
            return Placement(display: id, frame: rect.offsetBy(dx: bounds.minX, dy: bounds.minY))
        case .window(let id):
            guard let frame = RecordingWindows.frame(of: id) else { return nil }
            var display = CGMainDisplayID()
            var count: UInt32 = 0
            CGGetDisplaysWithPoint(CGPoint(x: frame.midX, y: frame.midY), 1, &display, &count)
            return Placement(display: count == 0 ? CGMainDisplayID() : display, frame: frame)
        }
    }

    private static func appKitFrame(_ quartz: CGRect) -> CGRect {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: quartz.minX, y: primaryHeight - quartz.maxY, width: quartz.width, height: quartz.height)
    }

    @concurrent
    private static func newFile(in folder: URL, as format: ScreenRecordingFormat) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return TimestampedFileName.freeURL("Screen Recording", extension: format.fileExtension, in: folder, at: .now)
    }
}
