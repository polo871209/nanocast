import SwiftUI

struct LauncherScreen: PaletteScreen {
    let appIndex: AppIndex
    let favorites: FavoritesStore
    let visibility: VisibilityStore
    let core: AppCore
    let vm: PaletteState
    let running: Bool
    let openActions: () -> Void
    let scrollToFollow: () -> Void

    private let results: [AppEntry]
    private let calc: CalcResult?
    private let color: ColorValue?
    private let pinsFavorites: Bool
    private let favoriteCount: Int
    private let suggestionCount: Int
    private let matchCount: Int
    private let files: [FileSearchResult]
    let rows: [Row]

    init(
        appIndex: AppIndex, favorites: FavoritesStore, visibility: VisibilityStore,
        currencyRates: CurrencyRateStore, core: AppCore, vm: PaletteState, running: Bool,
        openActions: @escaping () -> Void,
        scrollToFollow: @escaping () -> Void
    ) {
        self.appIndex = appIndex
        self.favorites = favorites
        self.visibility = visibility
        self.core = core
        self.vm = vm
        self.running = running
        self.openActions = openActions
        self.scrollToFollow = scrollToFollow

        let pinned = vm.argumentEntryID.flatMap(core.customCommands.command(entryID:))
            .map(AppEntry.init).flatMap { $0.name == vm.query ? $0 : nil }
        let ordered =
            pinned.map { AppIndex.Results(entries: [$0], matchCount: 1) }
            ?? appIndex.orderedResults(
                query: vm.query, visibility: visibility, favorites: favorites, hotKeys: core.hotKeys)
        var results = ordered.entries
        var matchCount = ordered.matchCount
        if pinned == nil, let browser = CommandCatalog.openInBrowser(for: vm.query),
            visibility.isVisible(browser)
        {
            results.insert(browser, at: 0)
            matchCount += 1
        }
        let calc =
            pinned == nil
            ? CalcMemo.evaluate(vm.query, rates: currencyRates.rates, format: core.calcNumberFormat) : nil
        let color = calc == nil && pinned == nil ? ColorValue.parse(vm.query) : nil
        let files = pinned == nil ? core.fileSearchCoordinator.launcherFiles(for: vm.query) : []
        let entries = results.map(Row.entry) + files.map(Row.file)
        let pinsFavorites = vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.results = results
        self.calc = calc
        self.files = files
        self.color = color
        self.pinsFavorites = pinsFavorites
        self.favoriteCount = pinsFavorites ? ordered.favoriteCount : 0
        self.suggestionCount = pinsFavorites ? ordered.suggestionCount : 0
        self.matchCount = matchCount
        if let calc {
            self.rows = [.calc(calc)] + entries
        } else if let color {
            self.rows = [.color(color)] + entries
        } else {
            self.rows = entries
        }
    }

    enum Row: Equatable, Identifiable {
        case calc(CalcResult)
        case color(ColorValue)
        case entry(AppEntry)
        case file(FileSearchResult)

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .color: return "color-card"
            case .entry(let app): return app.id
            case .file(let result): return "file-" + result.id
            }
        }
    }

    private func row(at selection: Int) -> Row? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    {
        guard let entry = entry(at: selection) else { return nil }
        if entry.kind == .customCommand {
            return CustomCommandArgumentsAccessory.make(
                command: core.customCommands.command(entryID: entry.id), vm: vm,
                metrics: core.settings.interfaceSize.metrics, focus: focus,
                onSubmit: { activate(at: selection) })
        }
        return nil
    }

    private func argumentValues(for entry: AppEntry) -> [String: String] {
        if entry.kind == .customCommand {
            guard let command = core.customCommands.command(entryID: entry.id) else { return [:] }
            return CustomCommandArgumentsAccessory.values(for: command, vm: vm)
        }
        return [:]
    }

    private func entry(at selection: Int) -> AppEntry? {
        guard case .entry(let app) = row(at: selection) else { return nil }
        return app
    }

    private func file(at selection: Int) -> FileSearchResult? {
        guard case .file(let result) = row(at: selection) else { return nil }
        return result
    }

    private func isCardSelected(_ selection: Int) -> Bool {
        switch row(at: selection) {
        case .calc, .color: return true
        case .entry, .file, nil: return false
        }
    }

    private var leadCard: LauncherList.LeadCard? {
        if let calc { return .calc(calc) }
        return color.map { .color($0) }
    }

    func hasPrimaryAction(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection) else { return true }
        return result.isActionable
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable ? CalcActionsMenu.content(result: result, core: core) : nil
        case .color(let color):
            return ColorActionsMenu.content(color: color, core: core)
        case .entry(let app):
            return AppActionsMenu.content(
                app: app, searchQuery: vm.query, core: core, running: running,
                favorites: favoriteActions(for: app, at: selection),
                onResetRanking: {
                    core.launcherCoordinator.resetRanking(for: app)
                    if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                },
                onHideFromSearch: { _ = hideFromSearch(at: selection) })
        case .file(let result):
            return FileSearchActionsMenu.content(result: result, core: core, target: vm.pasteTarget)
        case nil:
            return nil
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        case .calc(let result): core.calculatorCoordinator.copyCalculatorResult(result)
        case .color(let color):
            core.clipboardCoordinator.copyColor(color, as: ColorFormat.primary(for: color))
        case .entry(let app):
            core.launcherCoordinator.launch(
                app, searchQuery: vm.query, arguments: argumentValues(for: app))
        case .file(let result): core.fileSearchCoordinator.open(result)
        case nil: break
        }
    }

    func secondary(at selection: Int) -> Bool {
        if case .calc(let result) = row(at: selection) {
            return core.calculatorCoordinator.putAnswerInSearchBar(result)
        }
        if let file = file(at: selection) {
            core.fileSearchCoordinator.showInFinder(file)
            return true
        }
        guard let app = entry(at: selection), app.canRevealInFinder else { return false }
        core.launcherCoordinator.showInFinder(app)
        return true
    }

    private func runningApplication(at selection: Int) -> AppEntry? {
        guard let app = entry(at: selection), app.kind == .application,
            core.runningApps.isRunning(app)
        else { return nil }
        return app
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if let file = file(at: selection),
            FileSearchActionsMenu.perform(shortcut, result: file, core: core)
        {
            return true
        }
        switch shortcut {
        case .toggleFavorite: return toggleFavorite(at: selection)
        case .hideFromSearch: return hideFromSearch(at: selection)
        case .quit, .forceQuit: return quit(at: selection, force: shortcut == .forceQuit)
        case .restart: return restart(at: selection)
        case .edit: return editItem(at: selection)
        case .favoriteSlot(let index): return launchFavorite(at: index)
        case .copyCalculation: return copyCalculation(at: selection)
        default: return false
        }
    }

    private func copyCalculation(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection), result.isActionable else { return false }
        core.calculatorCoordinator.copyCalculationWithExpression(result)
        return true
    }

    private func quit(at selection: Int, force: Bool) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.quit(app, force: force)
        return true
    }

    private func restart(at selection: Int) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.restart(app)
        return true
    }

    private func editItem(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        switch entry.kind {
        case .customCommand:
            guard let command = core.customCommands.command(entryID: entry.id) else { return false }
            core.customCommandCoordinator.editCustomCommand(command)
        default: return false
        }
        return true
    }

    private func toggleFavorite(at selection: Int) -> Bool {
        guard let app = entry(at: selection), !CommandCatalog.isQueryDriven(app) else { return false }
        let removed = favoriteIndex(of: app)
        favorites.toggle(app)
        guard pinsFavorites else { return true }
        selectFavorite(at: removed.map { $0 - 1 } ?? 0)
        return true
    }

    private func launchFavorite(at index: Int) -> Bool {
        guard let app = pinnedFavorites.dropFirst(index).first else { return false }
        core.launcherCoordinator.launch(app)
        return true
    }

    private var pinnedFavorites: ArraySlice<AppEntry> { results.prefix(favoriteCount) }

    func moveFavorite(_ delta: Int, at selection: Int) -> Bool {
        guard let app = entry(at: selection), let index = favoriteIndex(of: app) else { return false }
        let target = index + delta
        guard target >= 0, target < favoriteCount else { return false }
        favorites.exchange(favorites.key(for: app), with: favorites.key(for: results[target]))
        follow(app)
        return true
    }

    private func favoriteActions(
        for app: AppEntry, at selection: Int
    )
        -> AppActionsMenu.FavoriteActions
    {
        let index = favoriteIndex(of: app)
        return AppActionsMenu.FavoriteActions(
            isFavorite: favorites.isFavorite(app),
            canMoveUp: index.map { $0 > 0 } ?? false,
            canMoveDown: index.map { $0 < favoriteCount - 1 } ?? false,
            toggle: { _ = toggleFavorite(at: selection) },
            move: { _ = moveFavorite($0, at: selection) })
    }

    private func favoriteIndex(of app: AppEntry) -> Int? {
        guard let index = results.firstIndex(of: app), index < favoriteCount else { return nil }
        return index
    }

    private func hideFromSearch(at selection: Int) -> Bool {
        guard let app = entry(at: selection), !CommandCatalog.isQueryDriven(app),
            let index = results.firstIndex(of: app)
        else { return false }
        if let id = CustomCommand.id(fromEntryID: app.id) {
            core.customCommandCoordinator.setCustomCommandShowsInRootSearch(false, id: id)
        } else if app.canHideFromSearch {
            visibility.setItemVisible(false, for: app)
        } else {
            return false
        }
        select(row: min(index, max(reorderedResults().entries.count - 1, 0)))
        return true
    }

    private func follow(_ app: AppEntry) {
        guard let index = reorderedResults().entries.firstIndex(of: app) else { return }
        select(row: index)
    }

    private func selectFavorite(at index: Int) {
        let count = reorderedResults().favoriteCount
        select(row: min(max(index, 0), max(count - 1, 0)))
    }

    private func reorderedResults() -> AppIndex.Results {
        appIndex.orderedResults(
            query: vm.query, visibility: visibility, favorites: favorites, hotKeys: core.hotKeys)
    }

    private func select(row index: Int) {
        vm.selection = index + (leadCard == nil ? 0 : 1)
        scrollToFollow()
    }

    func isRunning(at selection: Int) -> Bool {
        guard let app = entry(at: selection) else { return false }
        return core.runningApps.isRunning(app)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        LauncherList(
            results: results,
            selectedRowID: row(at: selection)?.id,
            favoriteCount: favoriteCount,
            suggestionCount: suggestionCount,
            matchCount: matchCount,
            scroll: scroll,
            card: leadCard,
            cardSelected: isCardSelected(selection),
            onActivateCard: {
                vm.selection = 0
                activate(at: 0)
            },
            onCardActions: {
                guard hasPrimaryAction(at: 0) else { return }
                vm.selection = 0
                openActions()
            },
            onActivate: {
                core.launcherCoordinator.launch(
                    $0, searchQuery: vm.query, arguments: argumentValues(for: $0))
            },
            onActions: { app in
                if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                openActions()
            },
            onDropped: { core.paletteCoordinator.dragLanded() },
            files: fileSection
        )
    }

    private var fileSection: LauncherList.FileSection? {
        guard !files.isEmpty else { return nil }
        return LauncherList.FileSection(
            results: files,
            onActivate: { activate(at: fileRow(at: $0)) },
            onActions: {
                vm.selection = fileRow(at: $0)
                openActions()
            })
    }

    private func fileRow(at index: Int) -> Int { rows.count - files.count + index }
}
