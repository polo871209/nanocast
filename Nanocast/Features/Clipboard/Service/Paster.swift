import AppKit
import Carbon.HIToolbox

enum Paster {
    static let nanocastEventTag: Int64 = 0x54494E59

    private static let activationDelay: TimeInterval = 0.08

    private static let directPostDelay: TimeInterval = 0.05

    @MainActor @discardableResult
    static func paste(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?
    ) -> Bool {
        guard write(item, store: store) else { return false }
        store.promote(item)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            postCommandV()
        }
        return true
    }

    @MainActor @discardableResult
    static func pastePlainText(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?
    ) -> Bool {
        guard let text = item.plainText else { return false }
        pasteString(text, previousApp: previousApp)
        store.promote(item)
        return true
    }

    @MainActor @discardableResult
    static func copy(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        guard write(item, store: store) else { return false }
        store.promote(item)
        return true
    }

    @MainActor @discardableResult
    static func copyPlainText(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        return pb.setString(text, forType: .string)
    }

    @MainActor
    static func pasteString(_ text: String, previousApp: NSRunningApplication?) {
        writeString(text)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            postCommandV()
        }
    }

    @MainActor
    static func copyString(_ text: String) {
        writeString(text)
    }

    @MainActor
    static func pasteStringInPlace(_ text: String, into app: NSRunningApplication?) {
        writeString(text)
        guard let pid = app?.processIdentifier else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + directPostDelay) {
            postCommandV(toPid: pid)
        }
    }

    @MainActor
    private static func writeString(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, ClipboardManager.internalType], owner: nil)
        pb.setString(text, forType: .string)
        pb.setData(Data(), forType: ClipboardManager.internalType)
    }

    @MainActor @discardableResult
    static func pasteInPlace(
        _ item: ClipboardItem, store: ClipboardStore, into app: NSRunningApplication?
    ) -> Bool {
        guard write(item, store: store) else { return false }
        if let pid = app?.processIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + directPostDelay) {
                postCommandV(toPid: pid)
            }
        }
        return true
    }

    @MainActor @discardableResult
    static func write(
        _ item: ClipboardItem, store: ClipboardStore, to pb: NSPasteboard = .general
    ) -> Bool {
        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            pb.clearContents()
            pb.declareTypes([.string, ClipboardManager.internalType], owner: nil)
            pb.setString(text, forType: .string)
        case .image:
            guard let url = store.imageURL(for: item),
                let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else {
                return false
            }
            pb.clearContents()
            pb.declareTypes([.png, .fileURL, ClipboardManager.internalType], owner: nil)
            pb.setData(data, forType: .png)
            // A text-only receiver ignores image data but pastes a file URL as its path.
            pb.setData(url.dataRepresentation, forType: .fileURL)
        case .file:
            guard let url = store.fileURL(for: item),
                FileManager.default.fileExists(atPath: url.path)
            else { return false }
            pb.clearContents()
            pb.declareTypes([.fileURL, .string, ClipboardManager.internalType], owner: nil)
            pb.setData(url.dataRepresentation, forType: .fileURL)
            pb.setString(url.path, forType: .string)
        }
        pb.setData(Data(), forType: ClipboardManager.internalType)
        return true
    }

    @MainActor
    static func postCommandV(toPid pid: pid_t? = nil) {
        guard Permissions.ensureAccessibility() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: nanocastEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: nanocastEventTag)

        if let pid {
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
