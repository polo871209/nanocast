import AppKit

@MainActor
enum WindowTarget {
    case external(NSRunningApplication)
    case own(NSWindow)

    static func current() -> WindowTarget? {
        if let own = NSApp.keyWindow.flatMap(placeable) { return .own(own) }
        return NSWorkspace.shared.frontmostApplication.map(WindowTarget.external)
    }

    static func behindPalette(
        ownWindow: NSWindow?, app: NSRunningApplication?
    ) -> WindowTarget? {
        if let own = ownWindow.flatMap(placeable) { return .own(own) }
        return app.map(WindowTarget.external)
    }

    private static func placeable(_ window: NSWindow) -> NSWindow? {
        [window, window.parent].compactMap { $0 }.first(where: isPlaceable)
    }

    private static func isPlaceable(_ window: NSWindow) -> Bool {
        window.isVisible && window.canBecomeMain && window.isMovable
    }
}
