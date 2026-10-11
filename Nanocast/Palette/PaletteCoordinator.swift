import AppKit

@MainActor
final class PaletteCoordinator {
    private let palette: PaletteState
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let fileSearch: FileSearchSession
    private let menuSearch: MenuSearchSession
    private let windowSwitch: WindowSwitchSession
    private let windowController: PaletteWindowController
    var onLauncherShown: (() -> Void)?
    var onScreenOpening: ((PaletteMode) -> Void)?

    init(
        palette: PaletteState,
        settings: AppSettings,
        appIndex: AppIndex,
        fileSearch: FileSearchSession,
        menuSearch: MenuSearchSession,
        windowSwitch: WindowSwitchSession,
        windowController: PaletteWindowController
    ) {
        self.palette = palette
        self.settings = settings
        self.appIndex = appIndex
        self.fileSearch = fileSearch
        self.menuSearch = menuSearch
        self.windowSwitch = windowSwitch
        self.windowController = windowController
    }

    var isVisible: Bool { windowController.isVisible }

    var panelFrame: CGRect? { windowController.visibleFrame }

    var anchorView: NSView? { windowController.anchorView }

    var targetApp: NSRunningApplication? {
        windowController.isVisible
            ? windowController.previousApp : NSWorkspace.shared.frontmostApplication
    }

    var previousOwnWindow: NSWindow? { windowController.previousOwnWindow }

    func isShowing(_ mode: PaletteMode) -> Bool {
        windowController.isVisible && palette.mode == mode
    }

    func togglePalette() {
        if isShowing(.launcher) {
            hidePalette()
        } else {
            showPalette(mode: .launcher, restoreAnyMode: true)
        }
    }

    func togglePalette(mode: PaletteMode) {
        if isShowing(mode) {
            hidePalette()
        } else {
            showPalette(mode: mode)
        }
    }

    func navigate(to mode: PaletteMode) {
        if windowController.isVisible, palette.mode != mode, mode != .launcher {
            palette.push(mode: mode)
        } else {
            palette.prepare(mode: mode)
        }
    }

    func showPalette(
        mode: PaletteMode, restoreAnyMode: Bool = false, seeding query: String? = nil
    ) {
        let preserved = windowController.consumePreservedState()
        let restoring = preserved && (restoreAnyMode || palette.mode == mode)
        let alreadyFresh = windowController.isPoppedToRoot && palette.mode == mode
        if query != nil || !(restoring || alreadyFresh) {
            navigate(to: mode)
        }
        if let query { palette.query = query }
        onScreenOpening?(palette.mode)
        windowController.show()
        if palette.mode == .fileSearch { fileSearch.search(palette.query) }
        if palette.mode == .menuSearch { menuSearch.filter(palette.query) }
        if palette.mode == .switchWindows { windowSwitch.filter(palette.query) }
        if palette.mode == .launcher {
            Task { await appIndex.refresh() }
            onLauncherShown?()
        }
    }

    func showArguments(of entry: AppEntry, values: [String: String]) {
        showPalette(mode: .launcher, seeding: entry.name)
        palette.argumentEntryID = entry.id
        for (field, value) in values {
            palette.commandArguments[PaletteState.ArgumentKey(entryID: entry.id, name: field)] = value
        }
        palette.pendingArgumentEntryID = entry.id
    }

    func hidePalette(restoreFocus: Bool = true) {
        menuSearch.reset()
        windowSwitch.reset()
        windowController.hide(restoreFocus: restoreFocus)
    }

    func dragLanded() {
        hidePalette(restoreFocus: false)
    }

    func popToRootNow() {
        windowController.popToRootNow()
    }

    var paletteIsCollapsed: Bool {
        settings.compactMode
            && !palette.forceExpanded
            && palette.mode == .launcher
            && palette.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func expandFromCompact() {
        palette.forceExpanded = true
    }

    func syncPaletteSize() {
        windowController.applyCollapsed(paletteIsCollapsed)
    }

    func beginPaletteDrag() {
        windowController.beginDrag()
    }

    func endPaletteDrag() {
        windowController.endDrag()
    }
}
