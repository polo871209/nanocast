import AppKit
import SwiftUI

@MainActor
final class ScreenDrawController {
    private enum Key {
        static let escape: UInt16 = 53
        static let tab: UInt16 = 48
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
    }

    private let session = ScreenDrawSession()
    private let end: () -> Void
    private var panels: [LiveCapturePanel] = []
    private var canvases: [ScreenDrawCanvasView] = []
    private let bar: LiveCapturePanel
    private var screensChanged: NotificationCenter.ObservationToken?

    init(metrics: InterfaceMetrics, end: @escaping () -> Void) {
        self.end = end
        weak var controller: ScreenDrawController?
        let content = FirstMouseHostingView(
            rootView: ScreenDrawToolbar(
                session: session, metrics: InterfaceMetrics(scale: metrics.scale * Theme.Markup.chromeScale),
                actions: .init(
                    choose: { controller?.choose($0) }, pick: { controller?.pick($0) },
                    undo: { controller?.perform { $0.undo() } }, clear: { controller?.perform { $0.clear() } },
                    hide: { controller?.toggleBar() }, end: end)))
        bar = LiveCapturePanel(frame: CGRect(origin: .zero, size: content.fittingSize))
        bar.level = NSWindow.Level(rawValue: NSWindow.Level.screenshot.rawValue + 1)
        bar.contentView = content
        controller = self
    }

    var canvasWindows: [CGWindowID] { panels.map { CGWindowID($0.windowNumber) } }

    func show() {
        let primaryHeight = NSScreen.primary?.frame.height ?? 0
        let painter = AnnotationAppearance.painter(scale: 1, mosaic: nil, face: ScreenDrawSession.textFace)
        let pointerScreen = NSScreen.underCursor
        for screen in NSScreen.screens {
            let frame = screen.frame
            let canvas = ScreenDrawCanvasView(
                globalFrame: CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height),
                scale: screen.backingScaleFactor, session: session, painter: painter,
                changed: { [weak self] in self?.render() }, endTextEverywhere: { [weak self] in self?.endText() })
            let panel = LiveCapturePanel(frame: frame)
            panel.ignoresMouseEvents = false
            panel.keyPressed = { [weak self] in self?.handle($0) ?? false }
            panel.contentView = canvas
            panel.orderFrontRegardless()
            panels.append(panel)
            canvases.append(canvas)
            if screen == pointerScreen { makeKey(panel) }
        }
        placeBar(on: pointerScreen)
        bar.orderFrontRegardless()
        NSCursor.crosshair.set()
        screensChanged = NotificationCenter.default.addObserver(
            of: NSApplication.self, for: .didChangeScreenParameters
        ) { [end] _ in end() }
    }

    func close() {
        if let screensChanged { NotificationCenter.default.removeObserver(screensChanged) }
        screensChanged = nil
        for panel in panels + [bar] {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels = []
        canvases = []
        NSCursor.arrow.set()
    }

    private func makeKey(_ panel: LiveCapturePanel) {
        panel.makeKeyAndOrderFront(nil)
        // A never-activated login item can drop the first key request, so re-assert.
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func placeBar(on screen: NSScreen?) {
        guard let visible = screen?.visibleFrame else { return }
        let size = bar.frame.size
        let origin = CGPoint(x: visible.maxX - size.width - Theme.Spacing.xl, y: visible.minY + Theme.Spacing.xl)
        bar.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private func toggleBar() {
        if bar.isVisible { bar.orderOut(nil) } else { bar.orderFrontRegardless() }
    }

    private func choose(_ tool: DrawTool) {
        endText()
        session.choose(tool)
    }

    private func pick(_ ink: AnnotationStyle.Ink) {
        session.pick(ink)
        render()
    }

    private func endText() {
        for canvas in canvases { canvas.endTextEdit() }
        session.endText()
        render()
    }

    private func perform(_ edit: (ScreenDrawSession) -> Void) {
        endText()
        edit(session)
        render()
    }

    private func render() {
        for canvas in canvases { canvas.render() }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let isCommand = modifiers.subtracting(.shift) == .command
        if session.board.editing != nil {
            guard isCommand, let key = ASCIIKeyboardLayout.character(for: event)?.lowercased() else { return false }
            return canvases.contains { $0.performTextCommand(key, shift: modifiers.contains(.shift)) }
        }
        if isCommand {
            switch ASCIIKeyboardLayout.character(for: event)?.lowercased() {
            case "z" where modifiers.contains(.shift): perform { $0.redo() }
            case "z": perform { $0.undo() }
            case "a" where !modifiers.contains(.shift): perform { $0.selectAll() }
            default: return false
            }
            return true
        }
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case Key.escape where session.hasSelection: perform { $0.deselect() }
        case Key.escape: end()
        case Key.tab: toggleBar()
        case Key.delete, Key.forwardDelete: perform { $0.hasSelection ? $0.deleteSelection() : $0.clear() }
        default:
            guard let character = ASCIIKeyboardLayout.character(for: event)?.lowercased().first,
                let key = DrawKey(character)
            else { return false }
            switch key {
            case .tool(let tool): choose(tool)
            case .ink(let ink): pick(ink)
            }
        }
        return true
    }
}
