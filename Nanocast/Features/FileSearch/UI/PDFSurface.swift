import PDFKit
import SwiftUI

struct PDFSurface: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PreviewPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document?.documentURL != url else { return }
        view.document = PDFDocument(url: url)
    }

    static func dismantleNSView(_ view: PDFView, coordinator: ()) {
        view.document = nil
    }
}

private final class PreviewPDFView: PDFView, KeyboardFocusRefusing {}
