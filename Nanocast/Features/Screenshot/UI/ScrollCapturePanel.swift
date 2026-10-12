import AppKit

final class ScrollCapturePanel: NSPanel {
    var keyPressed: ((NSEvent) -> Bool)?

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenshot
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        isMovable = false
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { keyPressed != nil }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if keyPressed?(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyPressed?(event) == true || super.performKeyEquivalent(with: event)
    }

    // AppKit otherwise pushes a borderless window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
