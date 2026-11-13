import CoreGraphics

enum AutoScrollRunner {
    /// The pointer jumps to `point`, because a posted scroll reaches only the window under the pointer.
    static func scroll(by points: Int32, at point: CGPoint) {
        guard
            let event = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -points, wheel2: 0, wheel3: 0)
        else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.location = point
        event.post(tap: .cghidEventTap)
    }

    /// Moves the pointer with a real mouse-moved event, so the app under it drops any hover state.
    static func movePointer(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    static var pointer: CGPoint? { CGEvent(source: nil)?.location }

    static var isMouseDown: Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
    }
}
