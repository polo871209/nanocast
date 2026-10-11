import AppKit

@MainActor
final class SettingsWindowChrome: WindowChrome {
    func install(in window: NSWindow) {
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        // `.automatic` draws a hairline once content scrolls under the bar, splitting the surface.
        window.titlebarSeparatorStyle = .none
        // Transparent opts the titlebar out of the system's glass band; Settings wants it drawn.
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
    }
}
