import CoreGraphics
import Foundation

struct PaletteFrame: Equatable {
    let mode: PaletteMode
    let query: String
    let selection: Int
}

@MainActor
@Observable
final class PaletteState {
    var mode: PaletteMode = .launcher { didSet { restoredSelection = nil } }
    private(set) var backStack: [PaletteFrame] = []
    var query: String = "" { didSet { restoredSelection = nil } }
    @ObservationIgnored private(set) var restoredSelection: Int?
    var selection: Int = 0
    var isComposing = false
    var clipboardFilter: ClipboardFilter = .all {
        didSet { if oldValue != clipboardFilter { restoredSelection = nil } }
    }
    var fileSearchFilter: FileSearchFilter = .all
    var emojiCategoryFilter: EmojiCategoryFilter = .all
    var emojiGridColumnsOverride: EmojiGridColumns?
    private(set) var isVisible = false
    var focusToken = UUID()
    var resetToken = UUID()
    var followToken = UUID()
    private(set) var queryRewriteToken = UUID()
    /// AppKit binds ⌘. to `cancelOperation:`, so the field editor eats it before `onKeyPress`.
    private(set) var pinChordToken = UUID()
    private(set) var favoriteSlotToken = UUID()
    private(set) var favoriteSlotIndex: Int?
    private(set) var emojiGridZoomToken = UUID()
    private(set) var emojiGridZoom: EmojiGridZoom?
    var forceExpanded = false
    var pasteTarget: PasteTarget?
    var commandArguments: [ArgumentKey: String] = [:]
    var pendingArgumentEntryID: String?
    var argumentEntryID: String?
    private(set) var commandHeld = false
    @ObservationIgnored private var commandHoldTask: Task<Void, Never>?
    private(set) var isEditingField = false
    @ObservationIgnored private(set) var hoverHighlightArmed = false
    private(set) var hoverDisarmToken = UUID()
    @ObservationIgnored private var hoverAnchor: CGPoint = .zero
    @ObservationIgnored var searchFieldFrame: CGRect = .zero
    @ObservationIgnored var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    var menuQuery = ""
    @ObservationIgnored var onMenuOpenChanged: ((Bool) -> Void)?
    private(set) var menuPresentationToken = UUID()

    func noteVisible(_ visible: Bool) {
        isVisible = visible
    }

    var canGoBack: Bool { !backStack.isEmpty }

    func prepare(mode: PaletteMode) {
        backStack.removeAll()
        replace(mode: mode)
    }

    private func replace(mode: PaletteMode) {
        openScreen(mode)
        resetToken = UUID()
    }

    func push(mode: PaletteMode) {
        if !self.mode.isNativeEditor {
            backStack.append(PaletteFrame(mode: self.mode, query: query, selection: selection))
        }
        replace(mode: mode)
    }

    func pop(preservingSelection: Bool = false) -> Bool {
        guard let frame = backStack.popLast() else { return false }
        openScreen(frame.mode)
        query = frame.query
        selection = frame.selection
        restoredSelection = preservingSelection ? frame.selection : nil
        followToken = UUID()
        return true
    }

    func pushCarryingQuery(mode: PaletteMode) {
        backStack.append(PaletteFrame(mode: self.mode, query: query, selection: selection))
        self.mode = mode
    }

    func collapseQueryLineBreaks() -> Bool {
        guard query.contains(where: \.isNewline) else { return false }
        query = query.split(whereSeparator: \.isNewline).joined(separator: " ")
        return true
    }

    func resetNavigation() {
        backStack.removeAll()
    }

    private func openScreen(_ mode: PaletteMode) {
        self.mode = mode
        query = ""
        selection = 0
        isComposing = false
        isEditingField = false
        commandArguments = [:]
        pendingArgumentEntryID = nil
        argumentEntryID = nil
        clipboardFilter = .all
        fileSearchFilter = .all
        emojiCategoryFilter = .all
        emojiGridColumnsOverride = nil
        forceExpanded = false
        dropHoverHighlight()
        menuOpen = false
        menuQuery = ""
        focusToken = UUID()
    }

    private static let commandHoldDelay = Duration.milliseconds(400)

    struct ArgumentKey: Hashable {
        let entryID: String
        let name: String
    }

    func notePinChord() {
        pinChordToken = UUID()
    }

    func noteMenuPresentation() {
        menuPresentationToken = UUID()
    }

    func rewriteQuery(_ text: String) {
        query = text
        queryRewriteToken = UUID()
    }

    func preserveSelection() {
        restoredSelection = selection
    }

    func noteFavoriteSlot(_ index: Int) {
        favoriteSlotIndex = index
        favoriteSlotToken = UUID()
    }

    func noteEmojiGridZoom(_ zoom: EmojiGridZoom) {
        emojiGridZoom = zoom
        emojiGridZoomToken = UUID()
    }

    func noteCommandHeld(_ held: Bool) {
        commandHoldTask?.cancel()
        commandHoldTask = nil
        guard held else {
            commandHeld = false
            return
        }
        guard !commandHeld else { return }
        commandHoldTask = Task { [weak self] in
            try? await Task.sleep(for: Self.commandHoldDelay)
            guard !Task.isCancelled else { return }
            self?.commandHeld = true
        }
    }

    func noteEditingField(_ editing: Bool) {
        guard editing != isEditingField else { return }
        isEditingField = editing
    }

    func notePointerMoved(to location: CGPoint) {
        guard !hoverHighlightArmed, HoverArming.isDeliberate(location, from: hoverAnchor) else {
            return
        }
        hoverHighlightArmed = true
    }

    func disarmHoverHighlight(pointerAt location: CGPoint) {
        hoverAnchor = location
        dropHoverHighlight()
    }

    private func dropHoverHighlight() {
        guard hoverHighlightArmed else { return }
        hoverHighlightArmed = false
        hoverDisarmToken = UUID()
    }
}
