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
    private let pinnedFavorites: [FavoritesStore.Item]
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
        let pinsFavorites = vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let pinnedFavorites = favorites.orderedItems(
            entries: Array(results.prefix(ordered.favoriteCount)),
            files: pinsFavorites ? core.fileSearchCoordinator.favoriteFiles : [])
        results.removeFirst(ordered.favoriteCount)
        let entries = pinnedFavorites.map(Row.init) + results.map(Row.entry) + files.map(Row.file)
        self.results = results
        self.calc = calc
        self.files = files
        self.color = color
        self.pinsFavorites = pinsFavorites
        self.pinnedFavorites = pinnedFavorites
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

        init(_ favorite: FavoritesStore.Item) {
            switch favorite {
            case .entry(let entry): self = .entry(entry)
            case .file(let file): self = .file(file)
            }
        }

        var favoriteKey: String? {
            switch self {
            case .entry(let entry):
                CommandCatalog.isQueryDriven(entry) ? nil : entry.preferenceKey
            case .file(let file): file.favoriteKey
            default: nil
            }
        }

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
                favorites: favoriteActions(for: .entry(app), at: selection),
                onResetRanking: {
                    core.launcherCoordinator.resetRanking(for: app)
                    if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                },
                onHideFromSearch: { _ = hideFromSearch(at: selection) })
        case .file(let result):
            return FileSearchActionsMenu.content(
                result: result, core: core, target: vm.pasteTarget,
                favorites: favoriteActions(for: .file(result), at: selection))
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
        if shortcut == .toggleFavorite { return toggleFavorite(at: selection) }
        if let file = file(at: selection),
            FileSearchActionsMenu.perform(shortcut, result: file, core: core)
        {
            return true
        }
        switch shortcut {
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
        guard let row = row(at: selection), row.favoriteKey != nil else { return false }
        let removed = favoriteIndex(of: row)
        switch row {
        case .entry(let entry): favorites.toggle(entry)
        case .file(let file): favorites.toggle(file)
        default: return false
        }
        guard pinsFavorites else { return true }
        selectFavorite(at: removed.map { $0 - 1 } ?? 0)
        return true
    }

    private func launchFavorite(at index: Int) -> Bool {
        guard pinnedFavorites.indices.contains(index) else { return false }
        activate(at: index + (leadCard == nil ? 0 : 1))
        return true
    }

    func moveFavorite(_ delta: Int, at selection: Int) -> Bool {
        guard let row = row(at: selection), let index = favoriteIndex(of: row) else { return false }
        let target = index + delta
        guard pinnedFavorites.indices.contains(target) else { return false }
        favorites.exchange(pinnedFavorites[index].key, with: pinnedFavorites[target].key)
        follow(row)
        return true
    }

    private func favoriteActions(
        for row: Row, at selection: Int
    )
        -> FavoriteActions
    {
        let index = favoriteIndex(of: row)
        return FavoriteActions(
            isFavorite: row.favoriteKey.map(favorites.keys.contains) ?? false,
            canMoveUp: index.map { $0 > 0 } ?? false,
            canMoveDown: index.map { $0 < pinnedFavorites.count - 1 } ?? false,
            toggle: { _ = toggleFavorite(at: selection) },
            move: { _ = moveFavorite($0, at: selection) })
    }

    private func favoriteIndex(of row: Row) -> Int? {
        pinnedFavorites.firstIndex { $0.id == row.id }
    }

    private func hideFromSearch(at selection: Int) -> Bool {
        guard let app = entry(at: selection), !CommandCatalog.isQueryDriven(app),
            let index = rows.firstIndex(of: .entry(app))
        else { return false }
        if let id = CustomCommand.id(fromEntryID: app.id) {
            core.customCommandCoordinator.setCustomCommandShowsInRootSearch(false, id: id)
        } else if app.canHideFromSearch {
            visibility.setItemVisible(false, for: app)
        } else {
            return false
        }
        select(row: min(index - (leadCard == nil ? 0 : 1), max(reorderedEntryRows().count - 1, 0)))
        return true
    }

    private func follow(_ row: Row) {
        guard let index = reorderedEntryRows().firstIndex(of: row) else { return }
        select(row: index)
    }

    private func selectFavorite(at index: Int) {
        let count = reorderedFavorites(in: reorderedResults()).count
        select(row: min(max(index, 0), max(count - 1, 0)))
    }

    private func reorderedResults() -> AppIndex.Results {
        appIndex.orderedResults(
            query: vm.query, visibility: visibility, favorites: favorites, hotKeys: core.hotKeys)
    }

    private func reorderedEntryRows() -> [Row] {
        let ordered = reorderedResults()
        let pinned = reorderedFavorites(in: ordered)
        return pinned.map(Row.init) + ordered.entries.dropFirst(ordered.favoriteCount).map(Row.entry)
    }

    private func reorderedFavorites(in ordered: AppIndex.Results) -> [FavoritesStore.Item] {
        favorites.orderedItems(
            entries: Array(ordered.entries.prefix(ordered.favoriteCount)),
            files: pinsFavorites ? core.fileSearchCoordinator.favoriteFiles : [])
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
            favorites: pinnedFavorites,
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
            onActivateFavorite: { _ = launchFavorite(at: $0) },
            onFavoriteActions: {
                vm.selection = $0 + (leadCard == nil ? 0 : 1)
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
