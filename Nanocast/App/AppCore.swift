import AppKit

@MainActor
@Observable
final class AppCore {
    static let shared = AppCore()

    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let customCommands = CustomCommandStore()
    let windowLayouts = WindowLayoutStore()
    let customWindowSizes = CustomWindowSizeStore()
    let rooms = RoomStore()
    let roomMinimums = RoomMinimumSizeStore()
    let roomParking = RoomParkingLedger(
        fileURL: AppPaths.applicationSupport().appendingPathComponent("room-parking.json"))
    let roomSession = RoomSession()
    let clipboardStore = ClipboardStore()
    @ObservationIgnored private var clipboardTextIndexer: ClipboardTextIndexer?
    let clipboardManager: ClipboardManager
    let textInjector: TextInjector
    let hotKeys = HotKeyManager()
    let dictationAudioDucker = DictationAudioDucker()
    @ObservationIgnored private(set) lazy var dictationModels =
        DictationModelStore(idleRelease: settings.dictationIdleRelease)
    @ObservationIgnored private(set) lazy var hyperKey = HyperKeyManager(
        settings: settings, hotKeys: hotKeys)
    @ObservationIgnored private lazy var dictationKey = DictationKeyManager(hotKeys: hotKeys)
    let windowMover = WindowMover()
    let spaceSwitcher = SpaceSwitcher()
    let inputSourceSwitcher = InputSourceSwitcher()
    let settings: AppSettings
    @ObservationIgnored private var settingsFile: SettingsFileRepository?
    @ObservationIgnored private var launcherSettingsFile: LauncherSettingsFile?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private let iconStyle = IconStyleMonitor()
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let aliases = AliasStore()
    let calcHistory = CalculatorHistoryStore()
    let currencyRates = CurrencyRateStore()
    let regionNumberFormat = RegionNumberFormatMonitor()
    let updateChecker = UpdateCheckStore()
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let pinnedEmoji = PinnedEmojiStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteState()
    let fileIndexer = FileIndexer()
    @ObservationIgnored private(set) lazy var fileSearch = FileSearchSession(index: fileIndexer.index)
    let dictionary = DictionarySession()
    let menuSearch = MenuSearchSession()
    let activationPolicy = ActivationPolicy()
    let uninstall = UninstallSession()
    let fileTools = FileToolsSession()
    let notesStore: NotesStore

    var pendingWindowLayoutEdit: WindowLayoutEditRequest?

    @ObservationIgnored private(set) lazy var dictationCoordinator = DictationCoordinator(
        settings: settings, hotKeys: hotKeys, models: dictationModels, injector: textInjector,
        audioDucker: dictationAudioDucker,
        confirmEnable: { [unowned self] in
            await self.confirm(
                title: "Enable Dictation?",
                message: """
                    Nanocast needs microphone access for dictation and Accessibility to paste into \
                    other apps. Audio is processed on this Mac.
                    """,
                symbol: "waveform", confirmTitle: "Continue", tone: .neutral,
                confirmRole: .standard)
        },
        showMessage: { [unowned self] in self.showMessage($0, tone: $1) })

    @ObservationIgnored private(set) lazy var paletteCoordinator = PaletteCoordinator(
        palette: palette, settings: settings, appIndex: appIndex,
        fileSearch: fileSearch, menuSearch: menuSearch,
        windowController: windowController)
    @ObservationIgnored private(set) lazy var settingsCoordinator = SettingsCoordinator(core: self)
    @ObservationIgnored private(set) lazy var onboardingCoordinator = OnboardingCoordinator(
        core: self)
    @ObservationIgnored private(set) lazy var systemActionCoordinator = SystemActionCoordinator(
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var uninstallCoordinator = UninstallCoordinator(
        session: uninstall, palette: palette, paletteCoordinator: paletteCoordinator,
        appIndex: appIndex, runningApps: runningApps, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases, core: self)
    @ObservationIgnored private(set) lazy var windowCommandCoordinator = WindowCommandCoordinator(
        settings: settings, paletteCoordinator: paletteCoordinator, windowMover: windowMover,
        spaceSwitcher: spaceSwitcher, customSizes: customWindowSizes)
    @ObservationIgnored private(set) lazy var customWindowSizeCoordinator =
        CustomWindowSizeCoordinator(
            store: customWindowSizes, settings: settings, appIndex: appIndex, hotKeys: hotKeys,
            favorites: favorites, visibility: visibility, ranking: launcherRanking,
            aliases: aliases, core: self)
    @ObservationIgnored private(set) lazy var windowShortcutPresetCoordinator =
        WindowShortcutPresetCoordinator(hotKeys: hotKeys, core: self)
    @ObservationIgnored private(set) lazy var windowLayoutCoordinator = WindowLayoutCoordinator(
        store: windowLayouts, settings: settings, appIndex: appIndex, hotKeys: hotKeys,
        favorites: favorites, visibility: visibility, ranking: launcherRanking, aliases: aliases,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        core: self)
    @ObservationIgnored private(set) lazy var roomCoordinator = RoomCoordinator(
        store: rooms, minimums: roomMinimums, ledger: roomParking, session: roomSession,
        settings: settings, appIndex: appIndex, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases, palette: palette,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var customCommandCoordinator = CustomCommandCoordinator(
        store: customCommands, settings: settings, appIndex: appIndex,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        hotKeys: hotKeys, favorites: favorites, visibility: visibility,
        ranking: launcherRanking, aliases: aliases, activationPolicy: activationPolicy, core: self)
    private nonisolated static let noteFormattingBarKey = "notesFormattingBarExpanded"
    @ObservationIgnored private(set) lazy var notesCoordinator = NotesCoordinator(
        store: notesStore,
        settings: settings,
        appIndex: appIndex,
        core: self,
        isFormattingBarExpanded: UserDefaults.standard.bool(forKey: Self.noteFormattingBarKey),
        saveFormattingBarExpanded: {
            UserDefaults.standard.set($0, forKey: Self.noteFormattingBarKey)
        })

    @ObservationIgnored private(set) lazy var launcherCoordinator = LauncherCoordinator(
        ranking: launcherRanking, windowController: windowController,
        paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator,
        customCommandCoordinator: customCommandCoordinator,
        systemActionCoordinator: systemActionCoordinator,
        windowCommandCoordinator: windowCommandCoordinator,
        windowLayoutCoordinator: windowLayoutCoordinator,
        fileSearchCoordinator: fileSearchCoordinator,
        menuSearchCoordinator: menuSearchCoordinator,
        notesCoordinator: notesCoordinator,
        core: self)
    @ObservationIgnored private(set) lazy var clipboardCoordinator = ClipboardCoordinator(
        clipboardStore: clipboardStore, clipboardManager: clipboardManager, settings: settings,
        appIndex: appIndex, palette: palette, windowController: windowController,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var emojiCoordinator = EmojiCoordinator(
        frequentEmoji: frequentEmoji, settings: settings, windowController: windowController,
        paletteCoordinator: paletteCoordinator)
    @ObservationIgnored private(set) lazy var calculatorCoordinator = CalculatorCoordinator(
        calcHistory: calcHistory, paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var fileSearchCoordinator = FileSearchCoordinator(
        settings: settings, appIndex: appIndex, session: fileSearch, indexer: fileIndexer,
        palette: palette, paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var fileToolsCoordinator = FileToolsCoordinator(
        settings: settings, appIndex: appIndex, session: fileTools, palette: palette,
        paletteCoordinator: paletteCoordinator, healthTicker: healthTicker, core: self)
    @ObservationIgnored private(set) lazy var menuSearchCoordinator = MenuSearchCoordinator(
        settings: settings, appIndex: appIndex, session: menuSearch, palette: palette,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private lazy var windowSwitchCoordinator = WindowSwitchCoordinator(
        settings: settings, hotKeys: hotKeys, healthTicker: healthTicker)
    @ObservationIgnored private(set) lazy var cameraCoordinator = CameraCoordinator(core: self)
    @ObservationIgnored private(set) lazy var colorPickerCoordinator = ColorPickerCoordinator(core: self)
    @ObservationIgnored private(set) lazy var screenshotCoordinator = ScreenshotCoordinator(core: self)
    @ObservationIgnored private(set) lazy var dictionaryCoordinator = DictionaryCoordinator(
        paletteCoordinator: paletteCoordinator)
    @ObservationIgnored private(set) lazy var updateCoordinator = UpdateCoordinator(
        store: updateChecker, core: self)

    @ObservationIgnored private lazy var windowController = PaletteWindowController(core: self)
    @ObservationIgnored private lazy var messageHUD = MessageHUDController(settings: settings)
    private(set) var isShowingDialog = false
    var isDimmingPaletteForDialog: Bool { isShowingDialog && windowController.isVisible }
    @ObservationIgnored private lazy var dialogs = DialogController(
        settings: settings,
        onPresentationChanged: { [weak self] isPresenting in
            guard let self else { return }
            isShowingDialog = isPresenting
        })
    private let healthTicker = HealthTicker()
    private var relaunchRequested = false

    private init() {
        let launcherRanking = LauncherRankingStore()
        let settings = AppSettings()
        self.launcherRanking = launcherRanking
        self.settings = settings
        appIndex = AppIndex(ranking: launcherRanking, aliases: aliases)
        let clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
        self.clipboardManager = clipboardManager
        textInjector = TextInjector(clipboardManager: clipboardManager)
        let noteSelectionKey = "notesActiveFileName"
        notesStore = NotesStore(
            repository: Self.notesRepository(for: settings),
            loadSelection: {
                UserDefaults.standard.string(forKey: noteSelectionKey).map(NoteID.init(rawValue:))
            },
            saveSelection: { UserDefaults.standard.set($0?.rawValue, forKey: noteSelectionKey) })
    }

    func start(launchedByUser: Bool) {
        Signposts.interval("AppCore.start") {
            UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
            NSApp.setActivationPolicy(.accessory)
            dictationAudioDucker.recover()
            applyAppearance()
            applyMotion()
            observeEffectiveAppearance()
            pinnedEmoji.onPersistenceFailure = { [weak self] in
                self?.showMessage("Couldn't save Emoji & Symbols pins", tone: .danger)
            }

            appIndex.start(settings: settings)
            clipboardCoordinator.applyEnabled()
            fileSearchCoordinator.applyEnabled()
            fileToolsCoordinator.applyEnabled()
            windowSwitchCoordinator.applyEnabled()
            menuSearchCoordinator.applyEnabled()
            fileSearchCoordinator.applyPolicy()
            notesCoordinator.applyEnabled()
            customCommands.onChange = { [weak self] _ in
                self?.customCommandCoordinator.applyCustomCommandsPresence()
            }
            customCommandCoordinator.applyCustomCommandsPresence()
            applyWindowCommandsPresence()
            customWindowSizes.onChange = { [weak self] _ in
                self?.customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            }
            customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            windowLayouts.onChange = { [weak self] _ in
                self?.windowLayoutCoordinator.applyWindowLayoutsPresence()
            }
            windowLayoutCoordinator.applyWindowLayoutsPresence()
            rooms.onChange = { [weak self] _ in self?.roomCoordinator.applyRoomsPresence() }
            roomCoordinator.applyRoomsPresence()
            roomCoordinator.recoverParkedWindows()
            paletteCoordinator.onScreenOpening = { [weak self] mode in
                switch mode {
                case .menuSearch: self?.menuSearchCoordinator.load()
                case .rooms, .roomWindows: self?.roomCoordinator.load()
                default: break
                }
            }
            updateCoordinator.applyEnabled()
            Task { await appIndex.refresh() }
            Task { await emojiIndex.load() }
            currencyRates.start()
            updateChecker.onUpdateAvailable = { [weak self] release in
                self?.updateCoordinator.presentIfAvailable(release) ?? true
            }
            updateCoordinator.applyAutomaticChecking()

            hyperKey.healthTicker = healthTicker
            dictationKey.healthTicker = healthTicker
            hotKeys.modifierTapMonitor.healthTicker = healthTicker

            hotKeys.onTogglePalette = { [weak self] in self?.paletteCoordinator.togglePalette() }
            hotKeys.dictationEnabled = settings.dictationEnabled
            hotKeys.dictationHoldToTalk = settings.dictationMode == .pushToTalk
            hotKeys.onDictationPressed = { [weak self] in self?.dictationCoordinator.pressed() }
            hotKeys.onDictationReleased = { [weak self] in self?.dictationCoordinator.released() }
            hotKeys.onDictationCancelled = { [weak self] in self?.dictationCoordinator.cancel() }
            hotKeys.onRunCommand = { [weak self] id in self?.launcherCoordinator.runCommand(id) }
            hotKeys.onRunCustomCommand = { [weak self] id in
                self?.customCommandCoordinator.runCustomCommand(id: id)
            }
            hotKeys.onRunSystemAction = { [weak self] id in
                self?.systemActionCoordinator.runSystemAction(id: id)
            }
            hotKeys.onRunWindowCommand = { [weak self] id in
                self?.windowCommandCoordinator.runWindowCommand(id: id)
            }
            hotKeys.onRunWindowLayout = { [weak self] id in
                self?.windowLayoutCoordinator.runWindowLayout(id: id)
            }
            hotKeys.onEnterRoom = { [weak self] id in self?.roomCoordinator.enterRoom(id: id) }
            hotKeys.onRunCustomWindowSize = { [weak self] id in
                self?.windowCommandCoordinator.runCustomWindowSize(id: id)
            }
            appIndex.onScan = { [weak self] in
                guard let self else { return }
                hotKeys.removeAppBindings(where: appIndex.isUninstalled)
                if settings.settingsFileEnabled, settingsFile == nil {
                    startSettingsFile(importing: true)
                } else if let launcherSettingsFile {
                    reportSettingsFileIssues(launcherSettingsFile.applyInstalled())
                }
            }
            hotKeys.displayName = { [weak self] action in self?.hotKeyDisplayName(for: action) }
            hotKeys.allowsAction = { [weak self] action in
                guard let self, visibility.allowsHotKey(action) else { return false }
                if action == .dictation { return settings.dictationEnabled }
                guard case .command(let id) = action else { return true }
                return appIndex.isCommandEnabled(id)
            }
            KeyShortcut.displayedHyperChord = { [settings] in
                guard settings.hyperKey != .none else { return nil }
                return KeyShortcut.hyperChord(includesShift: settings.hyperKeyIncludesShift)
            }
            SystemActionRunner.onAsyncFailure = { [weak self] id, failure in
                self?.systemActionCoordinator.presentSystemActionFailure(id: id, failure: failure)
            }
            hotKeys.start(
                customCommandIDs: Set(customCommands.commands.map(\.id)),
                windowLayoutIDs: Set(windowLayouts.layouts.map(\.id)),
                windowRoomIDs: Set(rooms.rooms.map(\.id)),
                customWindowSizeIDs: Set(customWindowSizes.sizes.map(\.id)))
            hyperKey.onProblem = { [weak self] in self?.showMessage($0, tone: .danger) }
            hyperKey.start()
            dictationKey.onProblem = { [weak self] in self?.showMessage($0, tone: .danger) }
            dictationKey.start()

            observeFeatureSwitches()

            if !OnboardingState.hasOnboarded {
                OnboardingState.markShown()
                onboardingCoordinator.showOnboarding()
            } else if launchedByUser {
                paletteCoordinator.showPalette(mode: .launcher)
            }
            if let version = updateChecker.takeInstalledVersion() {
                showMessage("Updated to Nanocast \(version.description)")
            }
        }
    }

    func handleReopen() {
        if settingsCoordinator.focusExisting() { return }
        if onboardingCoordinator.focusExisting() { return }
        if updateCoordinator.focusExisting() { return }
        if customCommandCoordinator.focusOutputWindow() { return }
        paletteCoordinator.showPalette(mode: .launcher)
    }

    private func hotKeyDisplayName(for action: HotKeyAction) -> String? {
        switch action {
        case .app(let bundleID):
            return appIndex.apps.first { $0.kind == .application && $0.bundleID == bundleID }?.name
        case .settingsPane(let bundleID):
            return appIndex.apps.first { $0.kind == .systemSettings && $0.bundleID == bundleID }?
                .name
        case .customCommand(let id):
            return customCommands.command(id: id)?.name
        case .windowLayout(let id):
            return windowLayouts.layout(id: id)?.name
        case .windowRoom(let id):
            return rooms.room(id: id)?.name
        case .customWindowSize(let id):
            return customWindowSizes.size(id: id)?.name
        case .togglePalette, .dictation, .windowSwitcher, .command, .systemAction, .windowCommand:
            return nil
        }
    }

    func flushNotesForTermination() async {
        await notesCoordinator.prepareForTermination()
    }

    func stopDictationForTermination() async {
        if settings.dictationEnabled { dictationCoordinator.prepareForTermination() }
        dictationAudioDucker.restoreImmediately()
        await dictationAudioDucker.waitForTransition()
        await dictationModels.stop()
    }

    func applyClipboardTextSearch() {
        guard settings.clipboardEnabled, settings.clipboardTextSearchEnabled else {
            clipboardStore.onItemsChanged = nil
            clipboardStore.onSearchResultsChanged = nil
            clipboardStore.setTextSearchEnabled(false)
            clipboardTextIndexer?.stop()
            return
        }
        guard clipboardStore.setTextSearchEnabled(true) else {
            showMessage(
                "Couldn't enable text recognition for clipboard history.",
                tone: .danger)
            return
        }
        clipboardStore.setTextSearchActive(palette.isVisible)
        let indexer =
            clipboardTextIndexer
            ?? ClipboardTextIndexer(store: clipboardStore, canRun: { ClipboardTextIndexer.isSystemIdle })
        clipboardTextIndexer = indexer
        clipboardStore.onItemsChanged = { [weak indexer] in indexer?.schedule() }
        clipboardStore.onSearchResultsChanged = { [weak self] query, previous, current in
            self?.clipboardCoordinator.followSearchResults(query: query, previous: previous, current: current)
        }
        indexer.start()
    }

    func relaunch() {
        guard !relaunchRequested else { return }
        relaunchRequested = true
        // AppKit's termination loop must start outside a Swift task or dispatch callback.
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }

    func prepareForTermination() {
        if settings.dictationEnabled { dictationCoordinator.prepareForTermination() }
        settingsFile?.flush()
        clipboardTextIndexer?.stop()
        hyperKey.prepareForTermination()
        dictationKey.prepareForTermination()
        windowLayoutCoordinator.prepareForTermination()
        roomCoordinator.prepareForTermination()
        inputSourceSwitcher.endSession()
        textInjector.prepareForTermination()
        if relaunchRequested { RelaunchRunner.relaunchAfterExit(Bundle.main.bundleURL) }
    }

    private func observeFeatureSwitches() {
        track(
            { _ = $0.automaticallyCheckForUpdates },
            reproject: { $0.updateCoordinator.applyAutomaticChecking() })
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowManagementShowInLauncher
            },
            reproject: {
                $0.applyWindowCommandsPresence()
                $0.customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            })
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowLayoutsShowInLauncher
            }, reproject: { $0.windowLayoutCoordinator.applyWindowLayoutsPresence() })
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowRoomsShowInLauncher
            }, reproject: { $0.roomCoordinator.applyEnabled() })
        track(
            {
                _ = $0.customCommandsEnabled
                _ = $0.customCommandsShowInLauncher
            }, reproject: { $0.customCommandCoordinator.applyCustomCommandsPresence() })
        track(
            { _ = $0.clipboardEnabled }, reproject: { $0.clipboardCoordinator.applyEnabled() })
        track(
            { _ = $0.clipboardTextSearchEnabled }, reproject: { $0.applyClipboardTextSearch() })
        track({ _ = $0.fileSearchEnabled }, reproject: { $0.fileSearchCoordinator.applyEnabled() })
        track(
            {
                _ = $0.fileToolsEnabled
                _ = $0.fileToolsFinderTab
            }, reproject: { $0.fileToolsCoordinator.applyEnabled() })
        track(
            { _ = $0.fileSearchShowInLauncher },
            reproject: { $0.fileSearchCoordinator.applyLauncherFiles() })
        track(
            {
                _ = $0.fileSearchScopes
                _ = $0.fileSearchIgnorePatterns
                _ = $0.fileSearchRemovedDefaultPatterns
            }, reproject: { $0.fileSearchCoordinator.applyPolicy() })
        track(
            { _ = $0.navigationEnabled },
            reproject: {
                $0.windowSwitchCoordinator.applyEnabled()
                $0.menuSearchCoordinator.applyEnabled()
            })
        track(
            hotKeys,
            {
                _ = $0.revision
                _ = $0.recordingAction
            }, reproject: { $0.windowSwitchCoordinator.applyTrigger() })
        track({ _ = $0.notesEnabled }, reproject: { $0.notesCoordinator.applyEnabled() })
        track(
            { _ = $0.notesShowsInMenuBar }, reproject: { $0.notesCoordinator.applyMenuBarItem() })
        track(
            { _ = $0.dictationIdleRelease },
            reproject: {
                $0.dictationModels.setIdleRelease($0.settings.dictationIdleRelease)
            })
        track(
            {
                _ = $0.dictationEnabled
                _ = $0.dictationMode
            },
            reproject: {
                $0.hotKeys.dictationHoldToTalk = $0.settings.dictationMode == .pushToTalk
                $0.hotKeys.dictationEnabled = $0.settings.dictationEnabled
            })
        track({ _ = $0.hyperKeyIncludesShift }, reproject: { $0.applyHyperChord() })
        track({ _ = $0.appearance }, reproject: { $0.applyAppearance() })
        track({ _ = $0.animationsEnabled }, reproject: { $0.applyMotion() })
        track({ _ = $0.interfaceSize }, reproject: { $0.windowController.applyInterfaceSize() })
        track(
            { _ = $0.clipboardRetention },
            reproject: { $0.clipboardCoordinator.applyRetention($0.settings.clipboardRetention) })
        track({ _ = $0.notesFolder }, reproject: { $0.applyNotesFolder() })
    }

    private func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    /// A built panel keeps the behaviour it was made with, so the live ones are re-pointed.
    private func applyMotion() {
        Motion.isEnabled = settings.animationsEnabled
        for case let panel as any AnimatedPanel in NSApp.windows {
            panel.followMotion()
        }
    }

    private func observeEffectiveAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial]) { app, _ in
            MainActor.assumeIsolated { IconCache.setDarkSurface(app.effectiveAppearance.isDark) }
        }
    }

    private func track(
        _ reads: @escaping @Sendable @MainActor (AppSettings) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        track(settings, reads, reproject: reproject)
    }

    private func track<Store: AnyObject & Sendable>(
        _ store: Store,
        _ reads: @escaping @Sendable @MainActor (Store) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        withObservationTracking {
            reads(store)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.track(store, reads, reproject: reproject)
                reproject(self)
            }
        }
    }

    private func applyHyperChord() {
        guard settings.hyperKey != .none else { return }
        hotKeys.retargetHyperBindings(includesShift: settings.hyperKeyIncludesShift)
    }

    private func applyNotesFolder() {
        let repository = Self.notesRepository(for: settings)
        Task { await notesStore.relocate(to: repository) }
    }

    private static func notesRepository(for settings: AppSettings) -> NotesRepository {
        NotesRepository(notesDirectory: AppPaths.contentFolder(settings.notesFolder, named: "Notes"))
    }

    private func applyWindowCommandsPresence() {
        let visible = settings.windowManagementEnabled && settings.windowManagementShowInLauncher
        appIndex.setWindowCommandsVisible(visible)
    }

    func startSettingsFile(importing: Bool) {
        guard settingsFile == nil else { return }
        let shortcuts = HotKeySettingsFile(hotKeys: hotKeys)
        let launcher = LauncherSettingsFile(
            appIndex: appIndex, aliases: aliases, visibility: visibility, shortcuts: shortcuts)
        let file = SettingsFileRepository(
            fileURL: AppPaths.settingsFile(),
            bindings: SettingsFileSchema.bindings(
                settings: settings,
                shortcuts: shortcuts, launcher: launcher,
                windowManagement: WindowManagementSettingsFile(
                    sizes: customWindowSizes, layouts: windowLayouts, rooms: rooms, aliases: aliases,
                    shortcuts: shortcuts)),
            commit: shortcuts.commit)
        file.onIssues = { [weak self] issues in self?.reportSettingsFileIssues(issues) }
        settingsFile = file
        launcherSettingsFile = launcher
        settings.settingsFileEnabled = true
        file.start(importing: importing)
    }

    func stopSettingsFile() {
        settingsFile?.flush()
        settingsFile = nil
        launcherSettingsFile = nil
        settings.settingsFileEnabled = false
    }

    private func reportSettingsFileIssues(_ issues: [SettingsFileIssue]) {
        guard let summary = SettingsFileIssue.summary(issues) else { return }
        showMessage(summary, tone: .danger)
    }

    var currentActivity: UpdateActivity {
        UpdateActivity(
            isInsertingText: textInjector.isDelivering,
            isUninstalling: uninstall.isTrashing,
            isRecordingHotKey: hotKeys.recordingAction != nil,
            isShowingDialog: isShowingDialog,
            isPaletteVisible: paletteCoordinator.isVisible)
    }

    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {
        await dialogs.notice(title: title, message: message, symbol: symbol, tone: tone)
    }

    func confirm(
        title: String, message: String?, symbol: String?, confirmTitle: String,
        tone: DialogTone = .danger, confirmRole: DialogAction.Role = .destructive,
        dismissTitle: String = "Cancel"
    ) async -> Bool {
        await dialogs.confirm(
            title: title, message: message, symbol: symbol, tone: tone, confirmTitle: confirmTitle,
            confirmRole: confirmRole, dismissTitle: dismissTitle)
    }

    func choose(
        title: String, message: String?, symbol: String?, options: [DialogAction],
        defaultIndex: Int, tone: DialogTone = .neutral
    ) async -> Int {
        await dialogs.choose(
            title: title, message: message, symbol: symbol, tone: tone, options: options,
            defaultIndex: defaultIndex)
    }

    func reportFailure(
        title: String, message: String, symbol: String, recovery: String?
    ) async
        -> Bool
    {
        await dialogs.reportFailure(
            title: title, message: message, symbol: symbol, recovery: recovery)
    }

    func showMessage(_ message: String, tone: DialogTone = .success) {
        messageHUD.show(message: message, tone: tone)
    }

    func showProgress(_ message: String) {
        messageHUD.showProgress(message: message)
    }

    func pickVolume(current: Float32) async -> Float32? {
        await dialogs.pickVolume(current: current)
    }

    func editClipboardText(_ text: String) async -> String? {
        await dialogs.editClipboardText(text)
    }
}
