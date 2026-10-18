import AppKit

@MainActor
final class AirDropTextSender: NSObject, NSSharingServiceDelegate {
    enum Failure: Error {
        case unavailable
        case unwritable
    }

    private var folder: URL?

    // macOS AirDrop refuses a bare string (`canPerform` is false), so the text travels as a file.
    func send(_ text: String) throws(Failure) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { throw .unavailable }
        discardFile()
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "AirDrop-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = folder.appending(
            path: "\(ClipboardTextFileName.stem(for: text)).txt", directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw .unwritable
        }
        self.folder = folder
        guard service.canPerform(withItems: [file]) else {
            discardFile()
            throw .unavailable
        }
        service.delegate = self
        service.perform(withItems: [file])
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        discardFile()
    }

    func sharingService(
        _ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error
    ) {
        discardFile()
    }

    private func discardFile() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
        self.folder = nil
    }
}
