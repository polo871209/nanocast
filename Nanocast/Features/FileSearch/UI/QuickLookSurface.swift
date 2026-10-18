import QuickLookUI
import SwiftUI

struct QuickLookSurface: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = PreviewQuickLookView(frame: .zero, style: .normal) ?? PreviewQuickLookView()
        view.autostarts = false
        view.shouldCloseWithWindow = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard view.previewItem as? URL != url else { return }
        view.previewItem = url as NSURL
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}

private final class PreviewQuickLookView: QLPreviewView, KeyboardFocusRefusing {}
