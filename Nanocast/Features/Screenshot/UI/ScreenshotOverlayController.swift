import AppKit
import SwiftUI

@MainActor
final class ScreenshotOverlayController {
    private let session: ScreenshotSession
    private let metrics: InterfaceMetrics
    private let perform: (ScreenshotIntent) -> Void
    private var panels: [ScreenshotPanel] = []
    private var canvases: [CaptureCanvasView] = []

    init(session: ScreenshotSession, metrics: InterfaceMetrics, perform: @escaping (ScreenshotIntent) -> Void) {
        self.session = session
        self.metrics = metrics
        self.perform = perform
    }

    func show(_ display: CapturedDisplay) {
        let panel = ScreenshotPanel(frame: display.frame)
        let canvas = canvas(for: display)
        panel.contentView = canvas
        let mouse = NSEvent.mouseLocation
        if NSMouseInRect(mouse, display.frame, false) {
            session.movePointer(
                to: CGPoint(x: mouse.x - display.frame.minX, y: display.frame.maxY - mouse.y), on: display.id)
        }
        present(panel, canvas: canvas)
        NSCursor.crosshair.set()
    }

    func showLongImage(_ display: CapturedDisplay, over screen: CGRect) {
        let panel = ScreenshotPanel(frame: screen)
        panel.isOpaque = false
        panel.backgroundColor = NSColor(Theme.Colors.captureDim)
        let content = NSView(frame: CGRect(origin: .zero, size: screen.size))
        let canvas = canvas(for: display, chromeHost: content)
        let margin = Theme.Spacing.xxl
        let size = CGSize(
            width: min(canvas.frame.width, screen.width - margin * 2),
            height: min(canvas.frame.height, screen.height - margin * 2))
        let scrollView = NSScrollView(
            frame: CGRect(
                origin: CGPoint(x: (screen.width - size.width) / 2, y: (screen.height - size.height) / 2), size: size))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = canvas
        content.addSubview(scrollView, positioned: .below, relativeTo: nil)
        panel.contentView = content
        present(panel, canvas: canvas)
        NSCursor.arrow.set()
    }

    private func canvas(for display: CapturedDisplay, chromeHost: NSView? = nil) -> CaptureCanvasView {
        CaptureCanvasView(
            display: display, session: session, metrics: metrics, chromeHost: chromeHost,
            changed: { [weak self] in self?.refresh() }, perform: perform)
    }

    private func present(_ panel: ScreenshotPanel, canvas: CaptureCanvasView) {
        panel.resignedKey = { [weak canvas] in canvas?.endTextEdit() }
        panels.append(panel)
        canvases.append(canvas)
        refresh()
        panel.orderFrontRegardless()
        guard panels.count == 1 else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(canvas)
        // A never-activated login item can drop the first key request, so re-assert.
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels = []
        canvases = []
        NSCursor.arrow.set()
    }

    func refresh() {
        for canvas in canvases { canvas.render() }
    }
}
