import AppKit
import SwiftUI

final class PinView: NSView {
    enum Action {
        case copy
        case save
        case close
    }

    private enum Key {
        static let escape: UInt16 = 53
    }

    private let naturalSize: CGSize
    private let act: (Action) -> Void

    init(image: CGImage, scale: CGFloat, act: @escaping (Action) -> Void) {
        naturalSize = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        self.act = act
        super.init(frame: CGRect(origin: .zero, size: naturalSize))
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .trilinear
        layer?.borderWidth = Theme.Size.hairline
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { return act(.close) }
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let step = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
        zoom(by: exp(event.scrollingDeltaY * step))
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification)
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == Key.escape else { return super.keyDown(with: event) }
        act(.close)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard event.type == .keyDown, modifiers == .command else { return super.performKeyEquivalent(with: event) }
        switch (ASCIIKeyboardLayout.character(for: event) ?? event.charactersIgnoringModifiers)?.lowercased() {
        case "c": act(.copy)
        case "s": act(.save)
        case "w": act(.close)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    private func zoom(by factor: CGFloat) {
        guard let window else { return }
        let frame = window.frame
        let width = min(max(frame.width * factor, naturalSize.width / 10, Theme.Size.pinMinimum), naturalSize.width * 8)
        let applied = width / frame.width
        let mouse = NSEvent.mouseLocation
        window.setFrame(
            CGRect(
                x: mouse.x - (mouse.x - frame.minX) * applied, y: mouse.y - (mouse.y - frame.minY) * applied,
                width: width, height: width * naturalSize.height / naturalSize.width),
            display: true)
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor(Theme.Colors.border).cgColor
        }
    }
}
