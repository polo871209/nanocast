import AppKit
import Carbon.HIToolbox
import SwiftUI

final class PalettePanel: NSPanel {
    enum HeaderFieldBoundary {
        case leading
        case trailing
    }

    /// Bare backspace, which the field editor swallows before `onKeyPress` could see it.
    var onBareBackspace: (() -> Bool)?
    /// Escape, which a focused form field answers before `onKeyPress` could see it.
    var onEscape: (() -> Bool)?
    var onCommandShortcut: ((NSEvent) -> Bool)?
    var onFieldEditorFocused: ((NSTextInputContext) -> Void)?
    var onHeaderFieldBoundaryArrow: ((HeaderFieldBoundary) -> Bool)?
    var onDismissMenu: (() -> Void)?
    private var dismissingMouseButton: Int?
    weak var paletteState: PaletteState? {
        didSet {
            paletteState?.onMenuOpenChanged = { [weak self] open in self?.setSearchCaretHidden(open) }
        }
    }

    var fieldEditorContext: NSTextInputContext? { fieldEditor?.inputContext }

    private var fieldEditor: NSTextView? { firstResponder as? NSTextView }

    func selectAllFieldEditorText() {
        fieldEditor?.selectAll(nil)
    }

    func moveFieldEditorCaretToEnd() {
        fieldEditor?.moveToEndOfDocument(nil)
    }

    private func headerFieldBoundary(for event: NSEvent) -> HeaderFieldBoundary? {
        guard event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            let editor = fieldEditor, editor.selectedRange().length == 0
        else { return nil }
        switch Int(event.keyCode) {
        case kVK_LeftArrow where editor.selectedRange().location == 0: return .leading
        case kVK_RightArrow where editor.selectedRange().location == (editor.string as NSString).length:
            return .trailing
        default: return nil
        }
    }

    private var compositionObserver: NotificationToken?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if let view = responder as? NSView, view.refusesKeyboardFocus { return false }
        guard super.makeFirstResponder(responder) else { return false }
        fieldEditor?.insertionPointColor = Self.caretColor
        trackComposition()
        if let context = fieldEditorContext { onFieldEditorFocused?(context) }
        return true
    }

    func trackComposition() {
        guard let editor = fieldEditor else {
            compositionObserver = nil
            paletteState?.isComposing = false
            return
        }
        paletteState?.isComposing = editor.hasMarkedText()
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: editor, queue: .main
        ) { [weak self, weak editor] _ in
            MainActor.assumeIsolated {
                self?.paletteState?.isComposing = editor?.hasMarkedText() ?? false
            }
        }
        compositionObserver = NotificationToken(token, center: center)
    }

    private static let menuNavKeys: Set<Int> = [
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab
    ]

    private static func emacsArrow(for event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]) == .control
        else { return nil }
        let arrow: (key: KeyEquivalent, code: Int)
        switch ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased()
        {
        case "n": arrow = (.downArrow, kVK_DownArrow)
        case "p": arrow = (.upArrow, kVK_UpArrow)
        case "f": arrow = (.rightArrow, kVK_RightArrow)
        case "b": arrow = (.leftArrow, kVK_LeftArrow)
        default: return nil
        }
        let characters = String(arrow.key.character)
        return NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: [.function, .numericPad],
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: event.isARepeat,
            keyCode: UInt16(arrow.code))
    }

    private static let caretColor = NSColor(Theme.Colors.textPrimary)

    private func setSearchCaretHidden(_ hidden: Bool) {
        guard let editor = fieldEditor else { return }
        editor.insertionPointColor = hidden ? .clear : Self.caretColor
        editor.updateInsertionPointStateAndRestartTimer(!hidden)
    }

    private static let cursorEvents: Set<NSEvent.EventType> = [
        .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged
    ]

    private func applyCursorPolicy(for event: NSEvent) {
        guard Self.cursorEvents.contains(event.type) else { return }
        let point = convertPoint(fromScreen: NSEvent.mouseLocation)
        let cursor = cursor(at: point)
        guard NSCursor.current !== cursor else { return }
        cursor.set()
    }

    func cursor(at point: NSPoint) -> NSCursor {
        if let contentView, isEditableText(in: contentView, at: point) { return .iBeam }
        guard paletteState?.mode.isNativeEditor != true else { return .arrow }
        // Outset: the field editor AppKit installs is a point taller than the field it serves.
        let text = searchFieldRect.insetBy(dx: -Self.fieldEditorSlack, dy: -Self.fieldEditorSlack)
        return text.contains(point) ? .iBeam : .arrow
    }

    private func isEditableText(in view: NSView, at point: NSPoint) -> Bool {
        let local = view.convert(point, from: nil)
        guard !view.isHidden, view.alphaValue > 0,
            view.bounds.intersection(view.visibleRect).contains(local)
        else { return false }
        if let field = view as? NSTextField { return field.isEditable }
        if let text = view as? NSTextView { return text.isEditable }
        return view.subviews.contains { isEditableText(in: $0, at: point) }
    }

    private static let fieldEditorSlack: CGFloat = 2

    private var searchFieldRect: CGRect {
        guard let frame = paletteState?.searchFieldFrame, !frame.isEmpty,
            let height = contentView?.bounds.height
        else { return .zero }
        return CGRect(
            x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    override func sendEvent(_ event: NSEvent) {
        if consumeMenuDismissal(event) { return }
        if event.type == .scrollWheel, paletteState?.mode.isNativeEditor == true {
            onDismissMenu?()
        }
        switch event.type {
        case .mouseMoved: paletteState?.notePointerMoved(to: NSEvent.mouseLocation)
        case .keyDown, .scrollWheel:
            paletteState?.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        case .flagsChanged:
            paletteState?.noteCommandHeld(event.modifierFlags.contains(.command))
        default: break
        }
        defer { applyCursorPolicy(for: event) }
        if event.type == .keyDown, let arrow = Self.emacsArrow(for: event) {
            sendEvent(arrow)
            return
        }
        if event.type == .keyDown,
            paletteState?.menuOpen == true,
            event.modifierFlags.isDisjoint(with: [.command, .control]),
            !Self.menuNavKeys.contains(Int(event.keyCode))
        {
            return
        }
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Escape,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            onEscape?() == true
        {
            return
        }
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Delete,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            fieldEditor?.hasMarkedText() != true,
            onBareBackspace?() == true
        {
            return
        }
        if event.type == .keyDown, let boundary = headerFieldBoundary(for: event),
            onHeaderFieldBoundaryArrow?(boundary) == true
        {
            return
        }
        if event.type == .keyDown,
            event.modifierFlags.contains(.command),
            onCommandShortcut?(event) == true
        {
            return
        }
        super.sendEvent(event)
    }

    private func consumeMenuDismissal(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            dismissingMouseButton = nil
            guard paletteState?.menuOpen == true, let onDismissMenu else { return false }
            dismissingMouseButton = event.buttonNumber
            onDismissMenu()
            return true
        case .leftMouseDragged, .rightMouseDragged, .leftMouseUp, .rightMouseUp:
            guard dismissingMouseButton == event.buttonNumber else { return false }
            if event.type == .leftMouseUp || event.type == .rightMouseUp {
                dismissingMouseButton = nil
            }
            return true
        default:
            return false
        }
    }
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0, width: Theme.Size.panelWidth, height: Theme.Size.panelHeight),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        level = .palette
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.sizingOptions = []
        contentView = hosting
    }

    override func resignKey() {
        super.resignKey()
        paletteState?.noteCommandHeld(false)
    }

    override var canBecomeKey: Bool { true }
    // The parent stays main while a menu is key, so its Liquid Glass remains active.
    override var canBecomeMain: Bool { true }
}
