import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

@MainActor
final class WindowSwitchController {
    private let panel = WindowSwitchPanel()
    private let metrics: () -> InterfaceMetrics

    init(metrics: @escaping () -> InterfaceMetrics) {
        self.metrics = metrics
    }

    func show(_ session: WindowSwitchSession, onChoose: @escaping (Int) -> Void) {
        guard let screen = Self.activeScreen() else { return }
        let grid = Self.grid(count: session.entries.count, on: screen)
        let host = NSHostingView(
            rootView: WindowSwitchView(session: session, grid: grid, onChoose: onChoose)
                .environment(\.metrics, metrics()))
        // Never size from `host.frame` after attaching: AppKit resets it to the content rect.
        let size = host.fittingSize
        host.setFrameSize(size)
        panel.setContentSize(size)
        panel.contentView = host
        let visible = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        panel.contentView = nil
    }

    private static func grid(count: Int, on screen: NSScreen) -> WindowSwitchGrid {
        let inset = Theme.Size.switcherSelectionInset * 2
        let tile = CGSize(
            width: Theme.Size.switcherThumbnail.width + inset,
            height: Theme.Size.switcherThumbnail.height + inset)
        let visible = screen.visibleFrame.size
        let fraction = Theme.Size.switcherScreenFraction
        return WindowSwitchGrid.fit(
            count: count, tile: tile, gap: Theme.Size.switcherGap,
            padding: Theme.Size.switcherPadding,
            bounds: CGSize(width: visible.width * fraction.width, height: visible.height * fraction.height),
            minimumScale: Theme.Size.switcherMinimumScale)
    }

    private static func activeScreen() -> NSScreen? {
        guard let front = NSWorkspace.shared.frontmostApplication.map(WindowInventory.owningProcess),
            let window = AXWindowAccess.targetWindow(
                in: AXWindowAccess.application(for: front.processIdentifier, timeout: 0.2)),
            let frame = AXWindowAccess.frame(of: window)
        else { return .underCursor }
        let center = AXGeometry(screens: NSScreen.screens).flip(frame)
        return NSScreen.screens.first { $0.frame.contains(CGPoint(x: center.midX, y: center.midY)) }
            ?? .underCursor
    }
}

private final class WindowSwitchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .palette
        hidesOnDeactivate = false
        animationBehavior = .none
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
