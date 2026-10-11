import AppKit

protocol KeyboardFocusRefusing: NSView {}

extension NSView {
    var refusesKeyboardFocus: Bool {
        sequence(first: self, next: { $0.superview }).contains { $0 is KeyboardFocusRefusing }
    }
}
