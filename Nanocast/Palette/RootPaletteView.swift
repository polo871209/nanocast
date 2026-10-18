import SwiftUI

struct RootPaletteView: View {
    @Environment(AppCore.self) private var core
    @Environment(PaletteState.self) private var vm
    @Environment(AppIndex.self) private var appIndex
    @Environment(ClipboardStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(VisibilityStore.self) private var visibility
    @Environment(CalculatorHistoryStore.self) private var calcHistory
    @Environment(CurrencyRateStore.self) private var currencyRates
    @Environment(EmojiIndex.self) private var emojiIndex
    @Environment(FrequentEmojiStore.self) private var frequentEmoji
    @Environment(FileSearchSession.self) private var fileSearch
    @Environment(DictionarySession.self) private var dictionary
    @Environment(MenuSearchSession.self) private var menuSearch
    @Environment(UninstallSession.self) private var uninstall
    @Environment(AppSettings.self) private var settings
    @Environment(\.metrics) private var metrics
    @FocusState private var searchFocused: Bool
    @FocusState private var argumentFocused: String?
    @State private var openMenu: OpenMenu?
    @State private var selectionIsRunning = false
    @State private var menuSelection = 0
    @State private var inputOptions: PopoverMenuContent?
    @State private var menuPanel = MenuPanelController()
    @State private var hostWindow: NSWindow?
    @State private var scroll = ScrollIntent(kind: .top)

    private var isCollapsed: Bool { core.paletteCoordinator.paletteIsCollapsed }

    private var screen: any PaletteScreen {
        switch vm.mode {
        case .launcher:
            return LauncherScreen(
                appIndex: appIndex, favorites: favorites, visibility: visibility,
                currencyRates: currencyRates, core: core, vm: vm, running: selectionIsRunning,
                openActions: openActions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .uninstall:
            return UninstallScreen(
                session: uninstall, core: core, vm: vm, openActions: openActions)
        case .emoji:
            return EmojiScreen(
                index: emojiIndex, frequent: frequentEmoji, pinned: core.pinnedEmoji, core: core, vm: vm,
                tone: settings.emojiSkinTone, defaultColumns: settings.emojiGridColumns,
                openActions: openActions)
        case .fileSearch:
            return FileSearchScreen(
                session: fileSearch, core: core, vm: vm, openActions: openActions)
        case .menuSearch:
            return MenuSearchScreen(session: menuSearch, core: core)
        case .rooms:
            return RoomsScreen(coordinator: core.roomCoordinator, session: core.roomSession, vm: vm)
        case .roomWindows:
            return RoomPickerScreen(
                coordinator: core.roomCoordinator, session: core.roomSession, vm: vm)
        case .customCommandEditor:
            return CustomCommandEditorScreen(
                coordinator: core.customCommandCoordinator, openMenuCorner: menuCorner,
                openInputMenu: openInputOptions)
        case .customCommands:
            return CustomCommandListScreen(
                store: core.customCommands, coordinator: core.customCommandCoordinator,
                vm: vm, metrics: metrics, openActions: openActions)
        case .clipboard:
            return ClipboardScreen(
                store: store, core: core, vm: vm, openActions: openActions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .dictionary:
            return DictionaryScreen(session: dictionary, core: core, vm: vm)
        case .calculatorHistory:
            return CalculatorHistoryScreen(
                history: calcHistory, currencyRates: currencyRates, core: core, vm: vm,
                openActions: openActions)
        }
    }

    private func selection(count: Int) -> Int {
        count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    private func selection(in screen: any PaletteScreen) -> Int {
        selection(count: screen.rows.count)
    }

    private var menuOpen: Bool { openMenu != nil }

    private var clipboardFilterContent: PopoverMenuContent {
        PopoverMenuContent(
            items: ClipboardFilter.allCases.enumerated().map { index, filter in
                PopoverMenuItem(
                    title: filter.title, systemImage: filter.systemImage,
                    startsSection: index == 1
                ) {
                    vm.clipboardFilter = filter
                }
            })
    }

    private var fileSearchFilterContent: PopoverMenuContent {
        PopoverMenuContent(
            items: FileSearchFilter.allCases.map { filter in
                PopoverMenuItem(title: filter.title, systemImage: filter.systemImage) {
                    vm.fileSearchFilter = filter
                }
            })
    }

    private var emojiCategoryContent: PopoverMenuContent {
        PopoverMenuContent(
            items: EmojiCategoryFilter.allCases.enumerated().map { index, filter in
                PopoverMenuItem(
                    title: filter.title, systemImage: filter.systemImage,
                    startsSection: index == 1
                ) {
                    vm.emojiCategoryFilter = filter
                }
            })
    }

    private var menuContent: PaletteMenuContent? {
        switch openMenu {
        case .actions:
            let screen = screen
            guard let content = screen.actions(at: selection(in: screen)) else { return nil }
            let filtered = content.matching(ActionMenuSearchQuery(vm.menuQuery))
            return PaletteMenuContent(
                popover: filtered.content, selection: $menuSelection,
                search: PopoverMenu.Search(
                    placeholder: "Search for actions…", placement: .bottom),
                onActivate: activateMenuItem, preferredSelection: filtered.bestMatch)
        case .clipboardFilter:
            return headerMenu(
                clipboardFilterContent, width: metrics.size.clipboardFilterMenuWidth)
        case .fileSearchFilter:
            return headerMenu(fileSearchFilterContent, width: metrics.size.fileSearchFilterMenuWidth)
        case .emojiCategory:
            return headerMenu(emojiCategoryContent, width: metrics.size.emojiCategoryMenuWidth)
        case .inputOptions(let corner):
            guard let inputOptions else { return nil }
            let width: CGFloat =
                switch corner {
                case .belowControl(let frame, _): max(metrics.size.formMenuMinimumWidth, frame.width)
                default: metrics.size.formMenuMinimumWidth
                }
            return headerMenu(
                inputOptions, width: width, extraRowsHeight: metrics.size.formMenuExtraRowsHeight)
        case nil: return nil
        }
    }

    var body: some View {
        let screen = screen
        let sel = selection(count: screen.rows.count)

        return keyHandlers(
            stateObservers(
                Group {
                    if isCollapsed {
                        Color.clear
                    } else {
                        screen.body(selection: sel, scroll: scroll)
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .overlay(alignment: .top) { topDragStrip }
                .background(
                    WindowReader {
                        hostWindow = $0
                        installHeaderArrowHandler(in: $0)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Theme.Colors.panelScrim)
                .background(GlassEffectView())
                .overlay {
                    Theme.Colors.dialogDimming
                        .opacity(core.isDimmingPaletteForDialog ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .animation(
                    .easeOut(
                        duration: core.isDimmingPaletteForDialog
                            ? Theme.Duration.dialogEnter : Theme.Duration.dialogExit),
                    value: core.isDimmingPaletteForDialog
                )
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous))),
            selection: sel)
    }

    @ViewBuilder
    private func emojiObservers(_ content: some View) -> some View {
        content
            .onChange(of: vm.emojiCategoryFilter) { land() }
            .onChange(of: core.pinnedEmoji.revision) { emojiGridChanged() }
            .onChange(of: (screen as? EmojiScreen)?.frequentlyUsed) { old, new in
                guard let old, let new else { return }
                (screen as? EmojiScreen)?.frequentlyUsedChanged(from: old, to: new)
                emojiGridChanged()
            }
            .onChange(of: vm.emojiGridColumnsOverride) { emojiGridChanged() }
            .onChange(of: settings.emojiGridColumns) { emojiGridChanged() }
            .onChange(of: vm.emojiGridZoomToken) {
                guard let zoom = vm.emojiGridZoom else { return }
                (screen as? EmojiScreen)?.zoom(zoom)
            }
    }

    private func emojiGridChanged() {
        guard vm.mode == .emoji else { return }
        scroll = ScrollIntent(kind: .follow)
        refreshActionsMenu()
    }

    @ViewBuilder
    private func stateObservers(_ content: some View) -> some View {
        emojiObservers(content)
            .onChange(of: vm.focusToken) {
                searchFocused = !screen.hidesSearchField
            }
            .modifier(PaletteHideObserver { if menuOpen { closeMenus() } })
            .onChange(of: vm.query) {
                if vm.collapseQueryLineBreaks() { return }
                land(restoringSelection: true)
                if vm.mode == .fileSearch { fileSearch.search(vm.query, filter: vm.fileSearchFilter) }
                if vm.mode == .launcher { core.fileSearchCoordinator.searchFromLauncher(vm.query) }
                if vm.mode == .dictionary { dictionary.lookUp(vm.query) }
                if vm.mode == .menuSearch { menuSearch.filter(vm.query) }
            }
            .onChange(of: vm.clipboardFilter) { land(restoringSelection: true) }
            .onChange(of: vm.fileSearchFilter) {
                land()
                fileSearch.search(vm.query, filter: vm.fileSearchFilter)
            }
            .onChange(of: vm.mode) {
                vm.clipboardFilter = .all
                vm.fileSearchFilter = .all
                vm.emojiCategoryFilter = .all
                vm.emojiGridColumnsOverride = nil
                if menuOpen { closeMenus() }
                land(restoringSelection: true)
                searchFocused = !screen.hidesSearchField
                if vm.mode != .uninstall { uninstall.cancel() }
                if vm.mode == .fileSearch {
                    fileSearch.search(vm.query, filter: vm.fileSearchFilter)
                } else if vm.mode == .launcher {
                    core.fileSearchCoordinator.searchFromLauncher(vm.query)
                } else {
                    fileSearch.cancel()
                }
                if vm.mode == .dictionary {
                    dictionary.lookUp(vm.query)
                } else {
                    dictionary.reset()
                }
                if vm.mode != .menuSearch { menuSearch.reset() }
                if vm.mode != .rooms, vm.mode != .roomWindows { core.roomCoordinator.screensDidClose() }
            }
            .onChange(of: vm.resetToken) {
                if menuOpen { closeMenus() }
                land()
            }
            .onChange(of: vm.pinChordToken) { performShortcut(.pin) }
            .onChange(of: vm.queryRewriteToken) {
                if menuOpen { closeMenus() }
                searchFocused = true
                Task { @MainActor in (hostWindow as? PalettePanel)?.moveFieldEditorCaretToEnd() }
            }
            .onChange(of: vm.favoriteSlotToken) {
                if let index = vm.favoriteSlotIndex { performShortcut(.favoriteSlot(index)) }
            }
            .onChange(of: openMenu) {
                guard menuOpen else { return }
                syncMenuPanel(presenting: true)
            }
            .onChange(of: menuSelection) { syncMenuPanel(presenting: false) }
            .onChange(of: vm.menuQuery) { menuQueryChanged() }
            .onDisappear {
                menuPanel.hide()
                (hostWindow as? PalettePanel)?.onHeaderFieldBoundaryArrow = nil
            }
            .onAppear {
                searchFocused = !screen.hidesSearchField
                land()
                focusPendingArgument()
            }
            .modifier(SearchFieldHiding(hidden: hidesSearchField, apply: applySearchFieldHiding))
            .onChange(of: core.paletteCoordinator.paletteIsCollapsed) {
                core.paletteCoordinator.syncPaletteSize()
            }
    }

    @ViewBuilder
    private func keyHandlers(_ content: some View, selection sel: Int) -> some View {
        content
            .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { press in
                if let reorder = movePinnedOrFavorite(1, modifiers: press.modifiers) { return reorder }
                if isCollapsed {
                    vm.selection = 0
                    core.paletteCoordinator.expandFromCompact()
                    return .handled
                }
                if menuOpen {
                    moveMenu(1)
                    return .handled
                }
                return moveVertically(1)
            }
            .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { press in
                if let reorder = movePinnedOrFavorite(-1, modifiers: press.modifiers) { return reorder }
                if isCollapsed { return .ignored }
                if menuOpen {
                    moveMenu(-1)
                    return .handled
                }
                return moveVertically(-1)
            }
            .onKeyPress(.leftArrow) {
                if menuOpen { return .handled }
                return moveHorizontally(-1) ? .handled : .ignored
            }
            .onKeyPress(.rightArrow) {
                if menuOpen { return .handled }
                return moveHorizontally(1) ? .handled : .ignored
            }
            .onKeyPress(keys: [.return, KeyEquivalent("\u{3}")], phases: .down) { press in
                let command = press.modifiers.contains(.command)
                let option = press.modifiers.contains(.option)
                if menuOpen, !command, !option {
                    activateMenuItem(menuSelection)
                    return .handled
                }
                if vm.mode.isNativeEditor { return .ignored }
                let screen = screen
                guard command || option else {
                    guard !vm.isComposing else { return .ignored }
                    let answersWithoutFocus = screen.hidesSearchField && screen.rows.isEmpty
                    guard searchFocused || answersWithoutFocus else { return .ignored }
                    activateSelection()
                    return .handled
                }
                let selection = selection(in: screen)
                if command, press.modifiers.contains(.control), screen.tertiary(at: selection) {
                    return .handled
                }
                if command, press.modifiers.contains(.shift),
                    screen.perform(.copyCalculation, at: selection)
                {
                    return .handled
                }
                if command { return screen.secondary(at: selection) ? .handled : .ignored }
                return screen.pasteKeepingWindowOpen(at: selection) ? .handled : .ignored
            }
            .onKeyPress(.escape) {
                switch PaletteEscapeAction.resolve(
                    menuOpen: menuOpen, menuQuery: vm.menuQuery,
                    argumentFocused: argumentFocused != nil, query: vm.query,
                    canGoBack: vm.canGoBack,
                    behavior: settings.escapeKeyBehavior)
                {
                case .clearMenuQuery, .closeMenu:
                    escapeMenu()
                case .leaveArgumentField:
                    returnFocusToSearchField()
                case .clearQuery:
                    vm.query = ""
                case .goBack:
                    goBack()
                case .hidePalette:
                    core.paletteCoordinator.hidePalette()
                    if settings.escapeKeyBehavior == .closeAndPopToRoot {
                        core.paletteCoordinator.popToRootNow()
                    }
                }
                return .handled
            }
            .onKeyPress(keys: [.tab], phases: .down) { press in
                if !menuOpen { advanceTabFocus(backwards: press.modifiers.contains(.shift)) }
                return .handled
            }
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.contains(.command),
                    ASCIIKeyboardLayout.matches(press.key, character: "k")
                else { return .ignored }
                guard !isCollapsed else { return .handled }
                let screen = screen
                guard !screen.rows.isEmpty || screen.actsWithoutRows else { return .handled }
                guard screen.hasPrimaryAction(at: selection(in: screen)) else { return .handled }
                guard screen.hasActions(at: selection(in: screen)) else { return .handled }
                toggleActions()
                return .handled
            }
            .onKeyPress(phases: .down) { press in
                let isDeleteKey = press.key == .delete || press.key == .deleteForward
                if isDeleteKey, menuOpen { return .handled }
                guard
                    let shortcut = PaletteShortcut.resolve(
                        command: press.modifiers.contains(.command),
                        shift: press.modifiers.contains(.shift),
                        option: press.modifiers.contains(.option),
                        control: press.modifiers.contains(.control),
                        isDeleteKey: isDeleteKey,
                        matches: { ASCIIKeyboardLayout.matches(press.key, character: $0) })
                else { return .ignored }
                guard !shortcut.requiresExpanded || !isCollapsed else { return .ignored }
                let screen = screen
                guard screen.perform(shortcut, at: selection(in: screen)) else { return .ignored }
                if shortcut.closesMenu, menuOpen { closeMenus() }
                return .handled
            }
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.contains(.command),
                    ASCIIKeyboardLayout.matches(press.key, character: "p")
                else { return .ignored }
                return performFilterAction() ? .handled : .ignored
            }
    }

    private var topDragStrip: some View {
        Color.clear
            .frame(height: metrics.size.headerPadding)
            .windowDraggable(settings.paletteDraggable, onBegan: beginDrag, onEnded: endDrag)
    }

    private func headerGutter(width: CGFloat) -> some View {
        Color.clear
            .frame(width: width)
            .windowDraggable(settings.paletteDraggable, onBegan: beginDrag, onEnded: endDrag)
    }

    private func beginDrag() { core.paletteCoordinator.beginPaletteDrag() }
    private func endDrag() { core.paletteCoordinator.endPaletteDrag() }

    private func applySearchFieldHiding(_ hidden: Bool) {
        searchFocused = !hidden
        if hidden { vm.query = "" }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            headerGutter(width: metrics.spacing.md * 2)
            if vm.mode != .launcher {
                HeaderBackButton(help: backHelp, action: goBack)
            } else {
                Image(systemName: vm.mode.systemImage)
                    .font(metrics.typography.headerIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.size.headerIconSlot)
                    .windowDraggable(settings.paletteDraggable, onBegan: beginDrag, onEnded: endDrag)
            }
            headerGutter(width: metrics.spacing.xl)
            headerField
            if let accessory = headerAccessory {
                accessory.view
                Spacer(minLength: 0).layoutPriority(-1)
            }
            if !isCollapsed, vm.mode == .clipboard {
                headerGutter(width: metrics.spacing.md)
                ClipboardFilterButton(
                    filter: vm.clipboardFilter, isOpen: openMenu == .clipboardFilter,
                    action: toggleClipboardFilter)
            }
            if !isCollapsed, vm.mode == .fileSearch {
                headerGutter(width: metrics.spacing.md)
                HeaderMenuButton(
                    title: vm.fileSearchFilter.title, systemImage: vm.fileSearchFilter.systemImage,
                    isOpen: openMenu == .fileSearchFilter,
                    help: "Filter by type  ⌘P",
                    action: toggleFileSearchFilter)
            }
            if !isCollapsed, vm.mode == .emoji {
                headerGutter(width: metrics.spacing.md)
                HeaderMenuButton(
                    title: vm.emojiCategoryFilter.title,
                    systemImage: vm.emojiCategoryFilter.systemImage,
                    isOpen: openMenu == .emojiCategory,
                    help: "Filter by category  ⌘P",
                    action: toggleEmojiCategory)
            }
            if isCollapsed, settings.showFavoritesInCompactMode,
                let launcher = screen as? LauncherScreen
            {
                let favorites = launcher.compactFavorites
                if !favorites.isEmpty {
                    headerGutter(width: metrics.spacing.md)
                    CompactFavoritesRow(
                        favorites: favorites,
                        showsOverflow: launcher.hasUnshownFavorites,
                        onLaunch: { core.launcherCoordinator.launch($0) },
                        onOverflow: { core.paletteCoordinator.expandFromCompact() }
                    )
                }
            }
            headerGutter(width: metrics.spacing.md * 2)
        }
        .frame(height: metrics.size.headerHeight)
        .padding(.top, metrics.size.headerPadding)
        .frame(maxWidth: .infinity)
        .onChange(of: vm.pendingArgumentEntryID) {
            Task { @MainActor in focusPendingArgument() }
        }
        .onChange(of: argumentFocused) { _, field in vm.noteEditingField(field != nil) }
    }

    private var headerAccessory: PaletteHeaderAccessory? {
        guard !isCollapsed else { return nil }
        let screen = screen
        return screen.headerAccessory(at: selection(in: screen), focus: $argumentFocused)
    }

    private var hidesSearchField: Bool { !isCollapsed && screen.hidesSearchField }

    private var headerField: some View {
        searchField
            .frame(minWidth: searchFieldFloor, maxWidth: searchFieldWidth)
            .opacity(hidesSearchField ? 0 : 1)
            .allowsHitTesting(!hidesSearchField)
            .accessibilityHidden(hidesSearchField)
            .onChange(of: hidesSearchField) { _, hidden in
                if hidden { vm.searchFieldFrame = .zero }
            }
    }

    private var searchFieldWidth: CGFloat? {
        if hidesSearchField { return nil }
        return headerAccessory.map(searchFieldWidth)
    }

    private var searchFieldFloor: CGFloat? {
        searchFieldWidth.map { min($0, metrics.size.searchFieldMinWidth) }
    }

    private func searchFieldWidth(for accessory: PaletteHeaderAccessory) -> CGFloat {
        let font = metrics.typography.searchFieldNSFont
        let text = vm.query.isEmpty ? searchPrompt : vm.query
        let typed = (text as NSString).size(withAttributes: [.font: font]).width
        let chrome = metrics.size.headerIconSlot + metrics.spacing.md * 3 + metrics.spacing.xl
        let room = metrics.size.panelWidth - accessory.width - chrome
        return min(
            max(typed + metrics.scaled(3), metrics.scaled(18)),
            max(room, metrics.size.searchFieldMinWidth))
    }

    private var searchPrompt: String {
        if headerAccessory != nil { return "" }
        return vm.mode.placeholder
    }

    private var searchField: some View {
        @Bindable var vm = vm
        return TextField("", text: $vm.query)
            .textFieldStyle(.plain)
            .font(metrics.typography.searchField)
            .tint(Theme.Colors.textPrimary)
            .focused($searchFocused)
            .frame(maxHeight: .infinity)
            .background(alignment: .leading) {
                // An IME's marked text leaves `query` empty, so the placeholder would overlap it.
                if vm.query.isEmpty, !vm.isComposing {
                    Text(searchPrompt)
                        .font(metrics.typography.searchField)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(Text(searchPrompt))
            .overlay {
                if settings.paletteDraggable {
                    EmptyFieldDragHandle(
                        isEmpty: vm.query.isEmpty && !vm.isComposing,
                        onBegan: beginDrag, onEnded: endDrag,
                        onClick: { searchFocused = true })
                }
            }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                vm.searchFieldFrame = hidesSearchField ? .zero : $0
            }
    }

    private func openActions() {
        let launcher = screen as? LauncherScreen
        selectionIsRunning = launcher.map { $0.isRunning(at: selection(in: $0)) } ?? false
        open(.actions, highlighting: 0)
    }

    private func toggleActions() {
        if openMenu == .actions {
            closeMenus()
        } else {
            openActions()
        }
    }

    private func toggleClipboardFilter() {
        if openMenu == .clipboardFilter {
            closeMenus()
            return
        }
        let active = ClipboardFilter.allCases.firstIndex(of: vm.clipboardFilter) ?? 0
        open(.clipboardFilter, highlighting: active)
    }

    private func toggleFileSearchFilter() {
        if openMenu == .fileSearchFilter {
            closeMenus()
            return
        }
        let active = FileSearchFilter.allCases.firstIndex(of: vm.fileSearchFilter) ?? 0
        open(.fileSearchFilter, highlighting: active)
    }

    private func performFilterAction() -> Bool {
        switch PaletteFilterAction.resolve(collapsed: isCollapsed, mode: vm.mode) {
        case .clipboardFilter: toggleClipboardFilter()
        case .fileSearchFilter: toggleFileSearchFilter()
        case .emojiCategory: toggleEmojiCategory()
        case .ignored: return false
        }
        return true
    }

    private func toggleEmojiCategory() {
        if openMenu == .emojiCategory {
            closeMenus()
            return
        }
        let active = EmojiCategoryFilter.allCases.firstIndex(of: vm.emojiCategoryFilter) ?? 0
        open(.emojiCategory, highlighting: active)
    }

    private func headerMenu(
        _ popover: PopoverMenuContent, width: CGFloat, extraRowsHeight: CGFloat = 0
    ) -> PaletteMenuContent {
        let filtered = popover.matching(ActionMenuSearchQuery(vm.menuQuery))
        return PaletteMenuContent(
            popover: filtered.content, selection: $menuSelection, width: width,
            search: PopoverMenu.Search(placeholder: "Search…", placement: .top),
            onActivate: activateMenuItem, preferredSelection: filtered.bestMatch,
            extraRowsHeight: extraRowsHeight)
    }

    private func open(_ menu: OpenMenu, highlighting row: Int) {
        vm.menuQuery = ""
        menuSelection = row
        vm.noteMenuPresentation()
        openMenu = menu
        vm.menuOpen = true
    }

    private func closeMenus() {
        menuPanel.hide()
        if menuOpen { searchFocused = !screen.hidesSearchField }
        openMenu = nil
        inputOptions = nil
        vm.menuQuery = ""
        vm.menuOpen = false
    }

    private func openInputOptions(
        _ content: PopoverMenuContent, corner: MenuPanelCorner, selection: Int
    ) {
        inputOptions = content
        open(.inputOptions(corner), highlighting: selection)
    }

    private func menuQueryChanged() {
        guard menuOpen, let content = menuContent else { return }
        let next =
            content.preferredSelection
            ?? (0..<content.rowCount).first(where: content.isSelectable) ?? 0
        if next != menuSelection { menuSelection = next }
        syncMenuPanel(presenting: false)
    }

    private func syncMenuPanel(presenting: Bool) {
        guard let content = menuContent, let corner = menuCorner else {
            menuPanel.hide()
            return
        }
        let view = content.view(corner)
        if presenting, let hostWindow {
            menuPanel.show(
                view, corner: corner, parent: hostWindow, core: core,
                clipPath: content.clipPath,
                onKeyDown: handleMenuPanelKey, onDismiss: closeMenus)
        } else {
            menuPanel.update(
                view, corner: corner, core: core, clipPath: content.clipPath)
        }
    }

    private func handleMenuPanelKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
        let navigationModifiers = modifiers.intersection([.command, .control, .option, .shift])
        if event.charactersIgnoringModifiers == "\u{1B}" {
            escapeMenu()
            return true
        }
        if vm.mode.isNativeEditor,
            (hostWindow as? PalettePanel)?.onCommandShortcut?(event) == true
        {
            return true
        }
        switch event.specialKey {
        case .some(.downArrow) where navigationModifiers.isEmpty:
            moveMenu(1)
            return true
        case .some(.upArrow) where navigationModifiers.isEmpty:
            moveMenu(-1)
            return true
        case .some(.carriageReturn), .some(.enter):
            let screen = screen
            let selection = selection(in: screen)
            if modifiers.contains([.command, .control]), screen.tertiary(at: selection) { return true }
            if modifiers.contains([.command, .shift]),
                screen.perform(.copyCalculation, at: selection)
            {
                return true
            }
            if modifiers.contains(.command) { return screen.secondary(at: selection) }
            if modifiers.contains(.option) {
                return screen.pasteKeepingWindowOpen(at: selection)
            }
            activateMenuItem(menuSelection)
            return true
        case .some(.tab), .some(.backTab):
            return true
        default:
            break
        }

        guard !modifiers.isDisjoint(with: [.command, .control]) else { return false }
        let character =
            ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased()
        if modifiers.contains(.control) {
            if character == "n" {
                moveMenu(1)
                return true
            }
            if character == "p" {
                moveMenu(-1)
                return true
            }
        }
        if modifiers.contains(.command), character == "k" {
            toggleActions()
            return true
        }
        if modifiers.contains(.command), character == "p", performFilterAction() { return true }
        if let shortcut = PaletteShortcut.resolve(
            command: modifiers.contains(.command), shift: modifiers.contains(.shift),
            option: modifiers.contains(.option), control: modifiers.contains(.control),
            isDeleteKey: false, matches: { character == String($0).lowercased() })
        {
            let screen = screen
            guard screen.perform(shortcut, at: selection(in: screen)) else { return false }
            if shortcut.closesMenu { closeMenus() }
            return true
        }
        if modifiers.contains(.command),
            (hostWindow as? PalettePanel)?.onCommandShortcut?(event) == true
        {
            return true
        }
        return false
    }

    private func escapeMenu() {
        if vm.menuQuery.isEmpty {
            closeMenus()
        } else {
            vm.menuQuery = ""
        }
    }

    private func refreshActionsMenu() {
        guard openMenu == .actions else { return }
        guard menuContent != nil else {
            closeMenus()
            return
        }
        syncMenuPanel(presenting: false)
    }

    private var menuCorner: MenuPanelCorner? {
        switch openMenu {
        case .actions: .bottomTrailing
        case .inputOptions(let corner): corner
        case .clipboardFilter, .fileSearchFilter, .emojiCategory:
            .belowHeaderTrailing
        case nil: nil
        }
    }

    private func land(restoringSelection: Bool = false) {
        let restored = restoringSelection ? vm.restoredSelection : nil
        let landing = restored.map { min($0, max(screen.rows.count - 1, 0)) } ?? screen.landingSelection
        vm.selection = landing
        scroll = ScrollIntent(kind: restored != nil ? .follow : landing == 0 ? .top : .center)
    }

    private func move(_ delta: Int, in screen: any PaletteScreen) {
        let count = screen.rows.count
        guard count > 0 else { return }
        vm.selection = min(max(selection(count: count) + delta, 0), count - 1)
        scroll = ScrollIntent(kind: .follow)
    }

    private func moveVertically(_ delta: Int) -> KeyPress.Result {
        let screen = screen
        guard !screen.ownsVerticalKeys(at: selection(in: screen)) else { return .ignored }
        if argumentFocused != nil { returnFocusToSearchField() }
        guard let next = screen.move(delta, axis: .vertical, from: selection(in: screen)) else {
            move(delta, in: screen)
            return .handled
        }
        vm.selection = next
        scroll = ScrollIntent(kind: .follow)
        return .handled
    }

    private func moveHorizontally(_ delta: Int) -> Bool {
        let screen = screen
        guard let next = screen.move(delta, axis: .horizontal, from: selection(in: screen)) else {
            return false
        }
        vm.selection = next
        scroll = ScrollIntent(kind: .follow)
        return true
    }

    private func movePinnedOrFavorite(
        _ delta: Int, modifiers: SwiftUI.EventModifiers
    ) -> KeyPress.Result? {
        guard modifiers.contains(.command), modifiers.contains(.option), !isCollapsed else {
            return nil
        }
        if let launcher = screen as? LauncherScreen {
            if launcher.moveFavorite(delta, at: selection(in: launcher)), menuOpen { closeMenus() }
            return .handled
        }
        guard let emoji = screen as? EmojiScreen else { return nil }
        emoji.movePin(delta, at: selection(in: emoji))
        return .handled
    }

    private func moveMenu(_ delta: Int) {
        guard let content = menuContent else { return }
        var row = menuSelection + delta
        while (0..<content.rowCount).contains(row) {
            if content.isSelectable(row) {
                menuSelection = row
                return
            }
            row += delta
        }
    }

    private func activateMenuItem(_ index: Int) {
        guard let content = menuContent, (0..<content.rowCount).contains(index) else { return }
        guard content.isSelectable(index) else { return }
        closeMenus()
        if argumentFocused == nil, !vm.mode.isNativeEditor { searchFocused = true }
        content.activate(index)
    }

    private func performShortcut(_ shortcut: PaletteShortcut) {
        let screen = screen
        _ = screen.perform(shortcut, at: selection(in: screen))
    }

    private func cycleMode() {
        switch PaletteTabAction.destination(from: vm.mode, clipboardEnabled: settings.clipboardEnabled) {
        case .launcher:
            vm.mode = .launcher
            vm.resetNavigation()
        case let mode: vm.pushCarryingQuery(mode: mode)
        }
    }

    private func advanceTabFocus(backwards: Bool) {
        let screen = screen
        if screen.tab(at: selection(in: screen), backwards: backwards) { return }
        if let next = screen.tabTarget(from: selection(in: screen), backwards: backwards) {
            vm.selection = next
            scroll = ScrollIntent(kind: .follow)
            return
        }
        guard let accessory = headerAccessory, !accessory.fieldNames.isEmpty else {
            return cycleMode()
        }
        // Read from the local value: a `@FocusState` set in this tick still reads back stale.
        let next = accessory.field(after: argumentFocused, backwards: backwards)
        argumentFocused = next
        searchFocused = next == nil
    }

    private func installHeaderArrowHandler(in window: NSWindow?) {
        guard let panel = window as? PalettePanel else { return }
        panel.onHeaderFieldBoundaryArrow = { boundary in
            guard !menuOpen, !isCollapsed,
                let accessory = headerAccessory, !accessory.fieldNames.isEmpty
            else { return false }
            switch boundary {
            case .leading:
                guard argumentFocused != nil else { return false }
                advanceTabFocus(backwards: true)
            case .trailing:
                advanceTabFocus(backwards: false)
            }
            return true
        }
    }

    private func returnFocusToSearchField() {
        argumentFocused = nil
        searchFocused = true
    }

    private func focusPendingArgument() {
        guard vm.pendingArgumentEntryID != nil,
            let field = headerAccessory?.firstIncompleteField
        else { return }
        argumentFocused = field
        searchFocused = false
        vm.pendingArgumentEntryID = nil
    }

    private var backHelp: String {
        vm.canGoBack
            ? "Esc to go back or ⌘ Esc to go to root search"
            : "Esc to close or ⌘ Esc to go to root search"
    }

    private func goBack() {
        if vm.mode == .customCommandEditor {
            core.customCommandCoordinator.cancelCustomCommandEditing()
            return
        }
        if !vm.pop() { core.paletteCoordinator.hidePalette() }
    }

    private func activateSelection() {
        guard !isCollapsed else { return }
        if let incomplete = headerAccessory?.firstIncompleteField {
            argumentFocused = incomplete
            searchFocused = false
            return
        }
        let screen = screen
        screen.activate(at: selection(in: screen))
    }

}

private enum OpenMenu: Equatable {
    case actions
    case inputOptions(MenuPanelCorner)
    case clipboardFilter
    case fileSearchFilter
    case emojiCategory
}

private struct PaletteHideObserver: ViewModifier {
    @Environment(PaletteState.self) private var vm
    let onHide: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: vm.isVisible) { _, visible in
            if !visible { onHide() }
        }
    }
}

private struct SearchFieldHiding: ViewModifier {
    let hidden: Bool
    let apply: (Bool) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: hidden) { _, hidden in apply(hidden) }
    }
}

private struct HeaderBackButton: View {
    let help: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(metrics.typography.headerIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: metrics.size.headerIconSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
        .help(help)
    }
}
