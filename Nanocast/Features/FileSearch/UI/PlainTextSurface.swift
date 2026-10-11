import AppKit
import SwiftUI

struct PlainTextSurface: NSViewRepresentable {
    let text: String

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.userFixedPitchFont(ofSize: 11)
            ?? .monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.textColor
    ]
    private static let inset = NSSize(width: 3, height: 3)

    final class Coordinator {
        var shown: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = Self.inset
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard context.coordinator.shown != text,
            let textView = scrollView.documentView as? NSTextView
        else { return }
        context.coordinator.shown = text
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: Self.attributes))
        textView.scroll(.zero)
    }
}
