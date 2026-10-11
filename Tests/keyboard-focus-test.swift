import AppKit

@main
@MainActor
struct KeyboardFocusTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    final class MarkedView: NSView, KeyboardFocusRefusing {}

    static func main() {
        theMarkedViewRefuses()
        aDescendantOfTheMarkRefuses()
        everythingElseAccepts()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func theMarkedViewRefuses() {
        expect(MarkedView().refusesKeyboardFocus, "the marked view itself refuses focus")
    }

    /// The real offender is `AVDesktopButton`, a private control the transport owns.
    static func aDescendantOfTheMarkRefuses() {
        let marked = MarkedView()
        let button = NSButton()
        let bar = NSView()
        bar.addSubview(button)
        marked.addSubview(bar)
        expect(button.refusesKeyboardFocus, "a control nested under the mark refuses focus too")
    }

    static func everythingElseAccepts() {
        let root = NSView()
        let field = NSTextField()
        let marked = MarkedView()
        root.addSubview(field)
        root.addSubview(marked)
        expect(!field.refusesKeyboardFocus, "a sibling of the mark still takes focus")
        expect(!root.refusesKeyboardFocus, "an ancestor of the mark still takes focus")
        expect(!NSView().refusesKeyboardFocus, "an unparented view takes focus")
    }
}
