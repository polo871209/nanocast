import AppKit

@MainActor
final class ActivationPolicy {
    private var openWindows: Set<ObjectIdentifier> = []

    var hasOpenWindows: Bool { !openWindows.isEmpty }

    func windowDidOpen(_ window: NSWindow) {
        openWindows.insert(ObjectIdentifier(window))
        NSApp.setActivationPolicy(.regular)
    }

    func windowDidClose(_ window: NSWindow) {
        openWindows.remove(ObjectIdentifier(window))
        if openWindows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    func closeAll() {
        for window in NSApp.windows where openWindows.contains(ObjectIdentifier(window)) {
            window.close()
        }
    }
}
