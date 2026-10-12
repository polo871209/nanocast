import AppKit
import SwiftUI

@MainActor
final class ScrollCaptureController {
    private enum Key {
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let space: UInt16 = 49
    }

    private struct Area {
        let displayID: CGDirectDisplayID
        let points: CGRect
        let pixels: PixelRect
        let scale: CGFloat
        let band: Int
    }

    private static let heightCap = 20_000
    private static let scrollbarBand: CGFloat = 16
    private static let stepShare: CGFloat = 0.45
    private static let firstStepShare: CGFloat = 0.2
    private static let smallestStepShare: CGFloat = 0.1
    private static let scrollPointHeightShare: CGFloat = 0.4
    private static let pointerSlop: CGFloat = 2
    private static let pointerArrival = Duration.milliseconds(100)
    private static let pointerPoll = Duration.milliseconds(5)
    private static let mouseDownPoll = Duration.milliseconds(100)
    private static let settleDelay = Duration.milliseconds(300)
    private static let settleInterval = Duration.milliseconds(120)
    private static let settleTries = 8
    private static let endConfirmations = 2
    private static let lostRetries = 3
    /// Some apps scale a scroll event. Each scroll measures by how much, within this range.
    private static let ratioRange: ClosedRange<CGFloat> = 0.25...4

    enum Outcome {
        case discarded
        case failed
        case captured(CGImage)
    }

    let session: ScrollCaptureSession
    private let area: Area
    private let file: ScrollStitchFile
    private var stitch = ScrollStitch(cap: heightCap)
    private var space: CGColorSpace?
    private let scrollPoint: CGPoint
    private var ratio: CGFloat = 1
    private var stepShare = firstStepShare
    private let border: ScrollCapturePanel
    private let bar: ScrollCapturePanel
    private var run: Task<Void, Never>?
    private var isEnded = false
    private let finish: (Outcome) -> Void

    init?(
        area pixels: PixelRect, on display: CapturedDisplay, metrics: InterfaceMetrics,
        finish: @escaping (Outcome) -> Void
    ) {
        guard let file = ScrollStitchFile(width: pixels.width) else { return nil }
        let points = display.points(pixels)
        area = Area(
            displayID: display.id, points: points, pixels: pixels, scale: display.scale,
            band: Int(Self.scrollbarBand * display.scale))
        session = ScrollCaptureSession(pointWidth: Int(points.width.rounded()), scale: display.scale)
        self.file = file
        self.finish = finish
        scrollPoint = CGPoint(
            x: display.quartzFrame.minX + points.midX,
            y: display.quartzFrame.minY + points.minY + points.height * Self.scrollPointHeightShare)
        func global(_ rect: CGRect) -> CGRect {
            CGRect(
                x: display.frame.minX + rect.minX, y: display.frame.maxY - rect.maxY, width: rect.width,
                height: rect.height)
        }
        let outset = -Theme.Size.captureBorder
        border = ScrollCapturePanel(frame: global(points.insetBy(dx: outset, dy: outset)))
        border.ignoresMouseEvents = true
        border.contentView = Self.borderView()
        let chrome = InterfaceMetrics(scale: metrics.scale * Theme.Markup.chromeScale)
        weak var controller: ScrollCaptureController?
        let content = NSHostingView(
            rootView: ScrollCaptureView(
                session: session, metrics: chrome, toggleScrolling: { controller?.toggleScrolling() },
                done: { controller?.end(keeping: true) }, discard: { controller?.end(keeping: false) }))
        let size = content.fittingSize
        bar = ScrollCapturePanel(
            frame: global(
                ChromePlacement.toolbar(
                    size: size, area: points, in: CGRect(origin: .zero, size: display.frame.size),
                    gap: Theme.Spacing.md)))
        bar.contentView = content
        controller = self
        bar.keyPressed = { controller?.handle($0) ?? false }
    }

    func show() {
        border.orderFrontRegardless()
        bar.makeKeyAndOrderFront(nil)
    }

    func end(keeping: Bool) {
        guard !isEnded else { return }
        isEnded = true
        run?.cancel()
        for panel in [border, bar] {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        Task { [run] in
            await run?.value
            guard keeping else { return finish(.discarded) }
            let image = space.flatMap { file.image(height: stitch.height, space: $0) }
            finish(image.map(Outcome.captured) ?? .failed)
        }
    }

    private func toggleScrolling() {
        if let run {
            run.cancel()
            return
        }
        guard session.status != .full else { return }
        session.status = .scrolling
        run = Task { [weak self] in
            await self?.scroll()
            self?.run = nil
        }
    }

    private func scroll() async {
        let status = await scrollToEnd()
        guard !isEnded else { return }
        session.status = Task.isCancelled ? .stopped : status
        if [.finished, .full].contains(session.status) { end(keeping: true) }
    }

    private func scrollToEnd() async -> ScrollCaptureSession.Status {
        if stitch.height == 0 {
            let first = await settledFrame()
            guard !Task.isCancelled else { return .stopped }
            guard let first else {
                end(keeping: true)
                return .lost
            }
            space = first.space
            await write(stitch.add(first.profile, expected: 0), of: first)
        }
        var stillFrames = 0
        var lostFrames = 0
        while !Task.isCancelled {
            let points = scrollPoints()
            await post(points)
            guard let frame = await settledFrame(), !Task.isCancelled else { return .stopped }
            let step = stitch.add(frame.profile, expected: Int((points * area.scale * ratio).rounded()))
            switch step {
            case .extended:
                await write(step, of: frame)
                let measured = CGFloat(stitch.lastOffset) / (points * area.scale)
                ratio = min(max(measured, Self.ratioRange.lowerBound), Self.ratioRange.upperBound)
                stepShare = Self.stepShare
                (stillFrames, lostFrames) = (0, 0)
            case .unchanged:
                stillFrames += 1
                if stillFrames >= Self.endConfirmations { return .finished }
            case .lost:
                lostFrames += 1
                if lostFrames > Self.lostRetries { return .lost }
                await post(-points)
                stepShare = max(stepShare / 2, Self.smallestStepShare)
            case .full:
                return .full
            case .started:
                return .lost
            }
        }
        return .stopped
    }

    private func scrollPoints() -> CGFloat {
        let rows = CGFloat(stitch.moving?.count ?? area.pixels.height) * stepShare
        return max((rows / area.scale / ratio).rounded(), 1)
    }

    private func post(_ points: CGFloat) async {
        while AutoScrollRunner.isMouseDown, !Task.isCancelled { try? await Task.sleep(for: Self.mouseDownPoll) }
        guard !Task.isCancelled else { return }
        let home = AutoScrollRunner.pointer
        AutoScrollRunner.scroll(by: Int32(points), at: scrollPoint)
        guard let home, !isNear(home, scrollPoint) else { return }
        let arrival = ContinuousClock.now + Self.pointerArrival
        while AutoScrollRunner.pointer.map({ !isNear($0, scrollPoint) }) ?? false, ContinuousClock.now < arrival {
            try? await Task.sleep(for: Self.pointerPoll)
        }
        AutoScrollRunner.movePointer(to: home)
    }

    private func isNear(_ point: CGPoint, _ other: CGPoint) -> Bool {
        hypot(point.x - other.x, point.y - other.y) <= Self.pointerSlop
    }

    private func settledFrame() async -> ScrollFrame? {
        try? await Task.sleep(for: Self.settleDelay)
        var last = await frame()
        for _ in 1..<Self.settleTries where !Task.isCancelled {
            try? await Task.sleep(for: Self.settleInterval)
            guard let next = await frame() else { return last }
            if let last, last.profile.isStill(comparedTo: next.profile) { return next }
            last = next
        }
        return last
    }

    private func frame() async -> ScrollFrame? {
        await ScrollFrameCapture.frame(
            display: area.displayID, area: area.points, pixelWidth: area.pixels.width,
            pixelHeight: area.pixels.height, band: area.band)
    }

    private func write(_ step: ScrollStitch.Step, of frame: ScrollFrame) async {
        session.record(height: stitch.height)
        await Self.write(step, of: frame, to: file)
    }

    @concurrent
    private static func write(_ step: ScrollStitch.Step, of frame: ScrollFrame, to file: ScrollStitchFile) async {
        file.write(step, of: frame)
    }

    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers.isEmpty, [Key.escape, Key.returnKey, Key.enter].contains(event.keyCode) {
            end(keeping: true)
        } else if modifiers.isEmpty, event.keyCode == Key.space {
            toggleScrolling()
        } else {
            return false
        }
        return true
    }

    private static func borderView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.borderWidth = Theme.Size.captureBorder
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.borderColor = NSColor(Theme.Colors.primaryAction).cgColor
        }
        return view
    }
}
