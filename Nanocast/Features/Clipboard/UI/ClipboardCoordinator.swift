import AppKit

@MainActor
final class ClipboardCoordinator {
    private let clipboardStore: ClipboardStore
    private let clipboardManager: ClipboardManager
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let palette: PaletteState
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    private var textTask: Task<Void, Never>?
    private var pasteSequence: PasteSequence?

    init(
        clipboardStore: ClipboardStore,
        clipboardManager: ClipboardManager,
        settings: AppSettings,
        appIndex: AppIndex,
        palette: PaletteState,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.clipboardStore = clipboardStore
        self.clipboardManager = clipboardManager
        self.settings = settings
        self.appIndex = appIndex
        self.palette = palette
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func applyEnabled() {
        appIndex.setCommandsVisible([.clipboardHistory, .pasteSequentially], settings.clipboardEnabled)
        guard settings.clipboardEnabled else {
            core.applyClipboardTextSearch()
            clipboardManager.stop()
            if palette.mode == .clipboard { palette.prepare(mode: .launcher) }
            clipboardStore.close()
            return
        }
        clipboardStore.open()
        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        clipboardManager.start()
        core.applyClipboardTextSearch()
        Task { clipboardStore.load() }
    }

    func followSearchResults(query: String, previous: [ClipboardItem], current: [ClipboardItem]) {
        guard palette.isVisible, palette.mode == .clipboard,
            palette.query.trimmingCharacters(in: .whitespaces) == query,
            previous.indices.contains(palette.selection)
        else { return }
        let selectedID = previous[palette.selection].id
        if let index = current.firstIndex(where: { $0.id == selectedID }) {
            palette.selection = index
        }
    }

    func applyRetention(_ retention: ClipboardRetention) {
        clipboardStore.maxAge = retention.maxAge
        clipboardStore.enforceLimits()
    }

    @discardableResult
    func activate(_ item: ClipboardItem, chord: ClipboardChord = .return) -> Bool {
        guard let action = settings.clipboardDefaultAction.action(for: chord, on: item) else {
            return false
        }
        perform(action, on: item)
        return true
    }

    func perform(_ action: ClipboardDefaultAction, on item: ClipboardItem) {
        switch action {
        case .paste: paste(item)
        case .copy: copyToClipboard(item)
        case .pastePlainText: pasteAsPlainText(item)
        }
    }

    func paste(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        if Paster.paste(item, store: clipboardStore, previousApp: previous) {
            selectClip(item)
        } else {
            reportUnavailable(item)
        }
    }

    func pasteAsPlainText(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        if Paster.pastePlainText(item, store: clipboardStore, previousApp: previous) {
            selectClip(item)
        }
    }

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        if !windowController.pasteKeepingWindowOpen(item, store: clipboardStore) {
            reportUnavailable(item)
        }
    }

    func pasteNextInSequence() {
        let now = Date()
        if let pasteSequence, pasteSequence.isSettling(at: now) { return }
        guard let target = paletteCoordinator.targetApp else { return }
        clipboardManager.prepareForNanocastPasteboardMutation()
        var sequence = continuingPasteSequence(at: now)
        while let item = sequence.next(in: clipboardStore.items) {
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette() }
            guard Paster.pasteInPlace(item, store: clipboardStore, into: target) else { continue }
            sequence.recordPaste(changeCount: NSPasteboard.general.changeCount, at: now)
            pasteSequence = sequence
            return
        }
        core.showMessage(String(localized: "Nothing left to paste"), tone: .neutral)
    }

    private func continuingPasteSequence(at now: Date) -> PasteSequence {
        let changeCount = NSPasteboard.general.changeCount
        if let pasteSequence, pasteSequence.continues(changeCount: changeCount, at: now) {
            return pasteSequence
        }
        return PasteSequence(history: clipboardStore.items, changeCount: changeCount, now: now)
    }

    private func reportUnavailable(_ item: ClipboardItem) {
        guard item.kind == .file else { return }
        core.showMessage(String(localized: "That file has moved or been deleted."), tone: .danger)
    }

    func deleteAllClips() async {
        guard
            await core.confirm(
                title: String(localized: "Delete All Entries"),
                message: String(
                    localized: """
                        Are you sure you want to proceed with deleting all clipboard history entries?
                        """),
                symbol: PaletteMode.clipboard.systemImage, confirmTitle: String(localized: "Delete All"))
        else { return }
        clearHistory()
    }

    func clearHistory() {
        clipboardStore.open()
        clipboardStore.clearAll()
        if !settings.clipboardEnabled { clipboardStore.close() }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        if Paster.copy(item, store: clipboardStore) {
            selectClip(item)
        } else {
            reportUnavailable(item)
        }
    }

    func copyColor(_ color: ColorValue, as format: ColorFormat) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(format.string(for: color))
    }

    func revealClip(_ item: ClipboardItem) {
        guard let url = clipURL(for: item) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(url)
    }

    func dragPayload(for item: ClipboardItem) -> ClipDragPayload? {
        let payload = item.dragPayload
        guard case .file = payload else { return payload }
        return clipURL(for: item).map(ClipDragPayload.file)
    }

    func openClip(_ item: ClipboardItem) {
        guard let url = clipURL(for: item) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.open(url)
    }

    func copyClipPath(_ item: ClipboardItem) {
        guard let path = item.filePath else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(path)
        core.showMessage(String(localized: "Copied path"))
    }

    func copyImageText(_ item: ClipboardItem) {
        guard let path = item.imagePath ?? item.filePath else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        core.showProgress(String(localized: "Reading text…"))
        let changeCount = NSPasteboard.general.changeCount
        textTask?.cancel()
        textTask = Task {
            do {
                let exists = await Task.detached { FileManager.default.fileExists(atPath: path) }.value
                try Task.checkCancellation()
                guard exists else {
                    return item.kind == .file
                        ? reportUnavailable(item)
                        : core.showMessage(
                            String(localized: "That image is no longer available."), tone: .danger)
                }
                let text = try await ClipboardTextWorker.extract(item)
                guard !text.isEmpty else {
                    return core.showMessage(String(localized: "No text found"), tone: .neutral)
                }
                guard NSPasteboard.general.changeCount == changeCount else {
                    return core.showMessage(
                        String(localized: "Clipboard changed, text not copied"), tone: .neutral)
                }
                Paster.copyPlainText(text)
                core.showMessage(String(localized: "Copied text"))
            } catch is CancellationError {
            } catch {
                core.showMessage(String(localized: "Couldn’t read the text"), tone: .danger)
            }
        }
    }

    private func clipURL(for item: ClipboardItem) -> URL? {
        let url = clipboardStore.imageURL(for: item) ?? clipboardStore.fileURL(for: item)
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            reportUnavailable(item)
            return nil
        }
        return url
    }

    func editClip(_ item: ClipboardItem) async {
        guard item.kind == .text else { return }
        guard let text = await core.editClipboardText(item.text ?? ""), !text.isEmpty else { return }
        do {
            guard let edited = try clipboardStore.updateText(text, of: item) else {
                Paster.copyPlainText(text)
                return
            }
            Paster.copy(edited, store: clipboardStore)
            guard palette.mode == .clipboard else { return }
            if !palette.clipboardFilter.matches(edited) { palette.clipboardFilter = .all }
            if clipboardStore.rowIndex(of: edited, in: palette.query, filter: palette.clipboardFilter) == nil {
                palette.query = ""
            }
            selectClip(edited)
            palette.preserveSelection()
            palette.followToken = UUID()
        } catch .tooLong {
            let limit = ClipboardStore.maxTextLength.formatted()
            core.showMessage(
                String(localized: "Too long to save. Keep it under \(limit) characters."), tone: .danger)
        } catch {
            core.showMessage(String(localized: "Couldn’t save the clipboard entry"), tone: .danger)
        }
    }

    func togglePinnedClip(_ item: ClipboardItem) {
        clipboardStore.togglePinned(item)
        selectClip(item)
        palette.followToken = UUID()
    }

    private func selectClip(_ item: ClipboardItem) {
        palette.selection =
            clipboardStore.rowIndex(
                of: item, in: palette.query, filter: palette.clipboardFilter) ?? 0
    }
}
