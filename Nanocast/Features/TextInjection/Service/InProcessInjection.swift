import AppKit

extension InjectableTextView {
    @MainActor
    func inject(_ text: String, over range: NSRange) {
        if let window, window.firstResponder !== self { window.makeFirstResponder(self) }
        insertText(text, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + text.utf16.count, length: 0))
        scrollRangeToVisible(selectedRange())
    }
}
