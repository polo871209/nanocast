import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class PaletteWindowController: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panel: PalettePanel?
    private(set) var previousApp: NSRunningApplication?
    private(set) weak var previousOwnWindow: NSWindow?
    private var popToRootTimer: Timer?
    private var queryWasPreserved = false
    private(set) var isPoppedToRoot = false
    private var anchor: CGPoint?
    private var drag: DragSession?
    private let dropGuides = PaletteDropGuideController()
    /// ⌘esc: the window server claims it, so no keystroke is left for the responder chain to see.
    private lazy var commandEscapeTap = CommandEscapeTap { [weak self] in
        guard let self, self.panel?.isKeyWindow == true else { return }
        self.core.palette.prepare(mode: .launcher)
    }

    private struct DragSession {
        var home: CGPoint
        var screenFrame: CGRect
        var visibleFrame: CGRect
        var displayKey: String
        var snap: PalettePlacement.Snap
        var verticalEntryY: CGFloat?
        var lastRawAnchor: CGPoint
        var lastSampleTime: TimeInterval?
        var moved = false
    }

    init(core: AppCore) {
        self.core = core
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var anchorView: NSView? { panel?.isVisible == true ? panel?.contentView : nil }

    var visibleFrame: CGRect? { panel.flatMap { $0.isVisible ? $0.frame : nil } }

    func show() {
        Signposts.interval("PaletteWindowController.show") {
            isPoppedToRoot = false
            core.palette.focusToken = UUID()
            let frontmost = NSWorkspace.shared.frontmostApplication
            let ownPID = NSRunningApplication.current.processIdentifier
            previousApp = frontmost?.processIdentifier == ownPID ? nil : frontmost
            let key = NSApp.keyWindow
            if key !== panel { previousOwnWindow = key }
            core.palette.pasteTarget = PasteTarget(app: previousApp)
            let panel = ensurePanel()
            if NSApp.modalWindow == nil { panel.level = .palette }
            core.palette.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
            anchor = nil
            positionPanel(panel, collapsed: core.paletteCoordinator.paletteIsCollapsed)
            panel.contentView?.layoutSubtreeIfNeeded()
            core.inputSourceSwitcher.beginSession(
                preferredInputSourceID: core.settings.autoSwitchInputSourceID)
            core.palette.noteVisible(true)
            core.clipboardStore.setTextSearchActive(true)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            // A never-activated login item can drop the first key request, so re-assert.
            DispatchQueue.main.async { [weak panel] in
                guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    private static func commandCharacter(from event: NSEvent) -> String? {
        guard !event.isARepeat,
            event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
        else { return nil }
        return ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased()
    }

    private static func emojiGridZoom(from event: NSEvent) -> EmojiGridZoom? {
        guard !event.isARepeat, event.modifierFlags.isDisjoint(with: [.option, .control]) else {
            return nil
        }
        switch ASCIIKeyboardLayout.character(for: event) {
        case "0": return .actualSize
        case "=", "+": return .zoomIn
        case "-": return .zoomOut
        default: return nil
        }
    }

    func hide(restoreFocus: Bool) {
        NotesPanel.refusesInheritedKey = previousOwnWindow?.isVisible != true
        panel?.orderOut(nil)
        NotesPanel.refusesInheritedKey = false
        commandEscapeTap.disable()
        core.inputSourceSwitcher.endSession()
        core.roomCoordinator.paletteDidHide()
        core.palette.noteVisible(false)
        core.clipboardStore.setTextSearchActive(false)
        anchor = nil
        drag = nil
        dropGuides.hide()
        ImageThumbnail.purgePreviews()
        FilePreviewThumbnail.purgePreviews()
        IconCache.purgeFitted()
        schedulePopToRoot()
        guard restoreFocus else { return }
        if let own = previousOwnWindow, own.isVisible {
            own.makeKeyAndOrderFront(nil)
        } else {
            previousApp?.activate()
        }
    }

    private func schedulePopToRoot() {
        popToRootTimer?.invalidate()
        let timeout = core.settings.popToRootTimeout
        guard timeout != .immediately else {
            popToRoot()
            return
        }
        popToRootTimer = Timer.scheduledTimer(withTimeInterval: timeout.interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.popToRootTimer = nil
                self.popToRoot()
            }
        }
    }

    private func popToRoot() {
        core.fileSearch.cancel()
        core.palette.prepare(mode: .launcher)
        isPoppedToRoot = true
    }

    func popToRootNow() {
        popToRootTimer?.invalidate()
        popToRootTimer = nil
        popToRoot()
    }

    func consumePreservedState() -> Bool {
        guard let timer = popToRootTimer else { return false }
        timer.invalidate()
        popToRootTimer = nil
        queryWasPreserved = true
        return true
    }

    @discardableResult
    func pasteKeepingWindowOpen(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        Paster.pasteInPlace(item, store: store, into: previousApp)
    }

    func pasteStringKeepingWindowOpen(_ text: String) {
        Paster.pasteStringInPlace(text, into: previousApp)
    }

    func windowDidResignKey(_ notification: Notification) {
        commandEscapeTap.disable()
        guard isVisible, !core.isShowingDialog else { return }
        if core.palette.menuOpen { return }
        if NSApp.modalWindow != nil {
            panel?.level = .normal
            return
        }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        commandEscapeTap.enable()
        panel?.level = .palette
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            panel?.trackComposition()
            if let context = panel?.fieldEditorContext {
                core.inputSourceSwitcher.applySession(to: context)
            }
            if queryWasPreserved {
                queryWasPreserved = false
                panel?.selectAllFieldEditorText()
            }
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        let moved = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        guard moved != anchor else { return }
        guard drag != nil else { anchor = moved; return }
        let snapped = trackDrag(to: moved)
        anchor = snapped
        if snapped != moved {
            panel.setFrameOrigin(CGPoint(x: snapped.x, y: snapped.y - panel.frame.height))
        }
    }

    func beginDrag() {
        guard let panel, let screen = panel.screen ?? targetScreen() else { return }
        let home = defaultAnchor(on: screen)
        let current = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let candidate = PalettePlacement.snapped(
            current, home: home, visibleFrame: screen.visibleFrame,
            expandedHeight: metrics.size.panelHeight,
            within: Theme.Size.paletteSnapDistance, previous: nil, speed: 0)
        let pixel = 1 / screen.backingScaleFactor
        let restingSnap = PalettePlacement.Snap(
            anchor: current,
            centeredX: candidate.centeredX && abs(candidate.anchor.x - current.x) <= pixel,
            height: abs(candidate.anchor.y - current.y) <= pixel ? candidate.height : nil)
        drag = DragSession(
            home: home, screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            displayKey: screen.displayKey, snap: restingSnap,
            lastRawAnchor: current, lastSampleTime: nil)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    func endDrag() {
        let session = drag
        drag = nil
        dropGuides.hide()
        guard let session, session.moved, let anchor else { return }
        if session.snap.centeredX && session.snap.height == .home {
            core.settings.setPalettePosition(nil, on: session.displayKey, expandedCenter: false)
            return
        }
        core.settings.setPalettePosition(
            PalettePlacement.offset(of: anchor, on: session.visibleFrame), on: session.displayKey,
            expandedCenter: session.snap.centeredX && session.snap.height == .expandedCenter)
    }

    private func trackDrag(to moved: CGPoint) -> CGPoint {
        guard var session = drag else { return moved }
        let now = ProcessInfo.processInfo.systemUptime
        let travel = hypot(moved.x - session.lastRawAnchor.x, moved.y - session.lastRawAnchor.y)
        let elapsed = session.lastSampleTime.map { now - $0 } ?? 1.0 / 60
        let speed = travel / max(elapsed, 0.001)
        session.lastRawAnchor = moved
        session.lastSampleTime = now
        if let screen = panel?.screen, screen.frame != session.screenFrame {
            session.screenFrame = screen.frame
            session.visibleFrame = screen.visibleFrame
            session.displayKey = screen.displayKey
            session.home = defaultAnchor(on: screen)
            session.snap = PalettePlacement.Snap(anchor: moved, centeredX: false, height: nil)
            session.verticalEntryY = nil
        }
        let snap = PalettePlacement.snapped(
            moved, home: session.home, visibleFrame: session.visibleFrame,
            expandedHeight: metrics.size.panelHeight, within: Theme.Size.paletteSnapDistance,
            previous: session.snap, speed: speed)
        let enteredVertical = snap.centeredX && !session.snap.centeredX
        let enteredHome = snap.height == .home && session.snap.height != .home
        if enteredVertical { session.verticalEntryY = moved.y }
        if let verticalEntryY = session.verticalEntryY,
            !snap.centeredX || abs(moved.y - verticalEntryY) > Theme.Size.dropGuideCombinedFlashTolerance
        {
            session.verticalEntryY = nil
        }
        if enteredVertical || (snap.height != nil && snap.height != session.snap.height) {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment, performanceTime: .drawCompleted)
        }
        if session.moved {
            dropGuides.move(
                home: session.home, screenFrame: session.screenFrame, dragged: snap.anchor)
        } else {
            dropGuides.show(
                home: session.home, width: metrics.size.panelWidth,
                screenFrame: session.screenFrame, dragged: snap.anchor)
        }
        if enteredHome {
            dropGuides.flash(session.verticalEntryY == nil ? .horizontal : .both)
            session.verticalEntryY = nil
        } else if enteredVertical {
            dropGuides.flash(.vertical)
        }
        session.snap = snap
        session.moved = true
        drag = session
        return snap.anchor
    }

    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }
        let root = RootPaletteView().paletteEnvironment(core)
        let panel = PalettePanel(rootView: root)
        panel.delegate = self
        panel.paletteState = core.palette
        panel.onFieldEditorFocused = { [weak self] context in
            self?.core.inputSourceSwitcher.applySession(to: context)
        }
        panel.onBareBackspace = { [weak self] in
            guard let core = self?.core, core.palette.query.isEmpty else { return false }
            if core.palette.isEditingField { return false }
            if core.palette.pop() { return true }
            guard core.palette.mode != .launcher else { return false }
            core.palette.prepare(mode: .launcher)
            return true
        }
        panel.onEscape = { [weak self] in
            guard let self else { return false }
            guard core.palette.mode == .customCommandEditor, !core.palette.isComposing else {
                return false
            }
            core.customCommandCoordinator.cancelCustomCommandEditing()
            return true
        }
        panel.onCommandShortcut = { [weak self] event in
            guard let self else { return false }
            if core.palette.mode.isNativeEditor,
                event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter,
                event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
                !core.palette.isComposing
            {
                core.customCommandCoordinator.saveCustomCommand()
                return true
            }
            if self.core.palette.mode == .emoji, let zoom = Self.emojiGridZoom(from: event) {
                self.core.palette.noteEmojiGridZoom(zoom)
                return true
            }
            guard Self.commandCharacter(from: event) != nil else { return false }
            if self.core.palette.mode == .launcher || self.core.palette.mode == .clipboard,
                let index = FavoriteSlots.index(forKeyCode: event.keyCode)
            {
                self.core.palette.noteFavoriteSlot(index)
                return true
            }
            guard let character = Self.commandCharacter(from: event) else { return false }
            switch character {
            case ",":
                self.core.settingsCoordinator.showSettings()
                return true
            case ".":
                self.core.palette.notePinChord()
                return true
            case "w":
                self.core.paletteCoordinator.hidePalette()
                return true
            default:
                return false
            }
        }
        self.panel = panel
        return panel
    }

    func applyCollapsed(_ collapsed: Bool) {
        guard let panel else { return }
        positionPanel(panel, collapsed: collapsed)
    }

    func applyInterfaceSize() {
        guard let panel else { return }
        anchor = nil
        positionPanel(panel, collapsed: core.paletteCoordinator.paletteIsCollapsed)
    }

    private func positionPanel(_ panel: NSPanel, collapsed: Bool) {
        guard let anchor = resolveAnchor() else { return }
        let size = metrics.size
        let height = collapsed ? size.compactHeight : size.panelHeight
        let frame = NSRect(
            x: anchor.x, y: anchor.y - height, width: size.panelWidth, height: height)
        panel.setFrame(frame, display: true)
    }

    private func targetScreen() -> NSScreen? {
        core.settings.openOnCursorScreen ? NSScreen.underCursor : NSScreen.primary
    }

    private func resolveAnchor() -> CGPoint? {
        if let anchor { return anchor }
        let resolved = targetScreen().flatMap { restoredAnchor(on: $0) ?? defaultAnchor(on: $0) }
        anchor = resolved
        return resolved
    }

    private func restoredAnchor(on screen: NSScreen) -> CGPoint? {
        guard let offset = core.settings.palettePosition(on: screen.displayKey) else { return nil }
        let stored = PalettePlacement.anchor(for: offset, on: screen.visibleFrame)
        let position =
            core.settings.paletteExpandedCenterDisplays.contains(screen.displayKey)
            ? CGPoint(
                x: defaultAnchor(on: screen).x,
                y: PalettePlacement.expandedCenterY(
                    in: screen.visibleFrame, expandedHeight: metrics.size.panelHeight))
            : stored
        return PalettePlacement.restored(
            position,
            graspable: CGSize(width: metrics.size.panelWidth, height: metrics.size.compactHeight),
            visibleFrame: screen.visibleFrame,
            minimumVisible: Theme.Size.paletteMinimumVisible)
    }

    private func defaultAnchor(on screen: NSScreen) -> CGPoint {
        PalettePlacement.defaultAnchor(
            in: screen.visibleFrame, width: metrics.size.panelWidth,
            topMarginFraction: Theme.Size.paletteTopMarginFraction)
    }

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
}

extension NSScreen {
    fileprivate var displayKey: String {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let id = number?.uint32Value else { return "primary" }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
            let string = CFUUIDCreateString(nil, uuid) as String?
        else { return String(id) }
        return string.lowercased()
    }
}
