import AppKit

@MainActor
final class LauncherCoordinator {
    private let ranking: LauncherRankingStore
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let customCommandCoordinator: CustomCommandCoordinator
    private let systemActionCoordinator: SystemActionCoordinator
    private let windowCommandCoordinator: WindowCommandCoordinator
    private let windowLayoutCoordinator: WindowLayoutCoordinator
    private let fileSearchCoordinator: FileSearchCoordinator
    private let menuSearchCoordinator: MenuSearchCoordinator
    private let notesCoordinator: NotesCoordinator
    private unowned let core: AppCore

    init(
        ranking: LauncherRankingStore,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        customCommandCoordinator: CustomCommandCoordinator,
        systemActionCoordinator: SystemActionCoordinator,
        windowCommandCoordinator: WindowCommandCoordinator,
        windowLayoutCoordinator: WindowLayoutCoordinator,
        fileSearchCoordinator: FileSearchCoordinator,
        menuSearchCoordinator: MenuSearchCoordinator,
        notesCoordinator: NotesCoordinator,
        core: AppCore
    ) {
        self.ranking = ranking
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.customCommandCoordinator = customCommandCoordinator
        self.systemActionCoordinator = systemActionCoordinator
        self.windowCommandCoordinator = windowCommandCoordinator
        self.windowLayoutCoordinator = windowLayoutCoordinator
        self.fileSearchCoordinator = fileSearchCoordinator
        self.menuSearchCoordinator = menuSearchCoordinator
        self.notesCoordinator = notesCoordinator
        self.core = core
    }

    func launch(
        _ app: AppEntry, searchQuery: String? = nil, arguments: [String: String] = [:]
    ) {
        if !CommandCatalog.isQueryDriven(app) {
            let term = searchQuery.flatMap {
                AppEntry.Kind.matching(by: LauncherOrder.CategoryQuery($0)).contains(app.kind) ? nil : $0
            }
            ranking.visit(itemKey: app.preferenceKey, query: term)
        }
        if app.kind == .command {
            guard let id = CommandCatalog.command(for: app) else { return }
            if id == .openInBrowser {
                paletteCoordinator.hidePalette(restoreFocus: false)
                AppLauncher.open(app.url)
                return
            }
            runCommand(id)
            return
        }
        if app.kind == .customCommand {
            guard let id = CustomCommand.id(fromEntryID: app.id) else { return }
            customCommandCoordinator.runCustomCommand(id: id, values: arguments)
            return
        }
        if app.kind == .systemAction {
            guard let action = SystemActionCatalog.action(forEntryID: app.id) else { return }
            systemActionCoordinator.runSystemAction(id: action.id)
            return
        }
        if app.kind == .windowCommand {
            if let command = WindowCommandCatalog.command(forEntryID: app.id) {
                windowCommandCoordinator.runWindowCommand(id: command.id)
                return
            }
            guard let id = CustomWindowSize.id(fromEntryID: app.id) else { return }
            windowCommandCoordinator.runCustomWindowSize(id: id)
            return
        }
        if app.kind == .windowRoom {
            guard let id = Room.id(fromEntryID: app.id) else { return }
            core.roomCoordinator.enterRoom(id: id)
            return
        }
        if app.kind == .windowLayout {
            guard let id = WindowLayout.id(fromEntryID: app.id) else { return }
            windowLayoutCoordinator.runWindowLayout(id: id)
            return
        }
        paletteCoordinator.hidePalette(restoreFocus: false)
        switch app.kind {
        case .application:
            AppLauncher.launch(app.url, allowsRunningApplicationSubstitution: false)
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .command, .customCommand, .systemAction, .windowCommand, .windowLayout,
            .windowRoom:
            break
        }
    }

    func runCommand(_ id: CommandID) {
        switch id {
        case .calculatorHistory:
            paletteCoordinator.togglePalette(mode: .calculatorHistory)
        case .clipboardHistory:
            paletteCoordinator.togglePalette(mode: .clipboard)
        case .pasteSequentially:
            core.clipboardCoordinator.pasteNextInSequence()
        case .searchEmoji:
            paletteCoordinator.togglePalette(mode: .emoji)
        case .searchFiles:
            fileSearchCoordinator.show()
        case .searchMenuItems:
            menuSearchCoordinator.show()
        case .openCamera:
            dismissPalette()
            Task { await core.cameraCoordinator.show() }
        case .define:
            core.dictionaryCoordinator.show()
        case .openInBrowser:
            break
        case .showNotes:
            dismissPalette()
            notesCoordinator.toggle()
        case .createNote:
            dismissPalette()
            notesCoordinator.createNote()
        case .searchNotes:
            dismissPalette()
            notesCoordinator.searchNotes()
        case .createWindowLayout:
            dismissPalette()
            windowLayoutCoordinator.editWindowLayout(nil)
        case .captureWindowLayout:
            dismissPalette()
            windowLayoutCoordinator.captureWindowLayout()
        case .switchRoom:
            core.roomCoordinator.showRooms()
        case .createRoom:
            core.roomCoordinator.createRoom()
        case .createCustomCommand:
            customCommandCoordinator.editCustomCommand(nil)
        case .searchCustomCommands:
            customCommandCoordinator.showCustomCommands()
        case .exportSettings:
            dismissPalette()
            Task { await BackupActions.runExportCommand(core: core) }
        case .importSettings:
            dismissPalette()
            Task { await BackupActions.runImportCommand(core: core) }
        case .importFromRaycast:
            dismissPalette()
            settingsCoordinator.showBackupSettings()
        case .checkForUpdates:
            dismissPalette()
            core.updateCoordinator.checkForUpdates()
        case .settings:
            dismissPalette()
            settingsCoordinator.showSettings()
        case .about:
            dismissPalette()
            settingsCoordinator.showAbout()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func dismissPalette() {
        guard paletteCoordinator.isVisible else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
    }

    func resetRanking(for app: AppEntry) {
        ranking.reset(itemKey: app.preferenceKey)
    }

    func showInFinder(_ app: AppEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    func restart(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await AppLauncher.restart(bundleID: bundleID, url: app.url) }
    }

    func quit(_ app: AppEntry, force: Bool = false) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        let quittingPreviousApp =
            windowController.previousApp?.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path
            == app.id
        guard AppLauncher.quit(bundleID: bundleID, url: app.url, force: force) else { return }
        paletteCoordinator.hidePalette(restoreFocus: !quittingPreviousApp)
    }
}
