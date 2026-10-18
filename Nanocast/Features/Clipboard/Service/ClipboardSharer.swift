import AppKit

@MainActor
final class ClipboardSharer: NSObject, @MainActor NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private var picker: NSSharingServicePicker?
    private var textFolder: URL?

    // AirDrop on macOS refuses a bare string (`canPerform` is false), so text is shared as a file.
    func share(text: String, from anchor: NSView) throws {
        discardTextFile()
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "clipboard-share-\(UUID().uuidString)", directoryHint: .isDirectory)
        textFolder = folder
        let file = folder.appending(path: "clipboard-share.txt", directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
        } catch {
            discardTextFile()
            throw error
        }
        share(file: file, from: anchor)
    }

    func share(file: URL, from anchor: NSView) {
        guard let provider = NSItemProvider(contentsOf: file) else { return discardTextFile() }
        let picker = NSSharingServicePicker(items: [provider])
        picker.delegate = self
        self.picker = picker
        picker.show(
            relativeTo: CGRect(x: anchor.bounds.maxX, y: anchor.bounds.midY, width: 0, height: 0),
            of: anchor, preferredEdge: .maxX)
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService
    ) -> (any NSSharingServiceDelegate)? {
        self
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?
    ) {
        if service == nil { discardTextFile() }
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        discardTextFile()
    }

    func sharingService(
        _ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error
    ) {
        discardTextFile()
    }

    private func discardTextFile() {
        guard let textFolder else { return }
        try? FileManager.default.removeItem(at: textFolder)
        self.textFolder = nil
    }
}
