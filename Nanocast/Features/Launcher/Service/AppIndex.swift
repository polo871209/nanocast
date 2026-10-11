import AppKit

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case application
        case systemSettings
        case command
        case customCommand
        case systemAction
        case windowCommand
        case windowLayout
        case windowRoom

        var descriptor: KindDescriptor {
            switch self {
            case .application:
                return KindDescriptor(
                    label: "Application", sectionTitle: "Applications",
                    openVerb: "Open Application", canHideFromSearch: true,
                    canRevealInFinder: true, canDragOut: true, isSymbolIcon: false, rankPriority: 4)
            case .systemSettings:
                return KindDescriptor(
                    label: "System Setting", sectionTitle: "System Settings",
                    openVerb: "Open System Setting", canHideFromSearch: true,
                    canRevealInFinder: true, canDragOut: false, isSymbolIcon: false, rankPriority: 1)
            case .command:
                return KindDescriptor(
                    label: "Command", sectionTitle: "Commands",
                    openVerb: "Run Command", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .customCommand:
                return KindDescriptor(
                    label: "Custom Command", sectionTitle: "Custom Commands",
                    openVerb: "Run Custom Command", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .systemAction:
                return KindDescriptor(
                    label: "System Action", sectionTitle: "System Actions",
                    openVerb: "Run System Action", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowCommand:
                return KindDescriptor(
                    label: "Window Command", sectionTitle: "Window Management",
                    openVerb: "Move Window", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowLayout:
                return KindDescriptor(
                    label: "Window Layout", sectionTitle: "Window Layouts",
                    openVerb: "Arrange Windows", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowRoom:
                return KindDescriptor(
                    label: "Room", sectionTitle: "Rooms", openVerb: "Enter Room",
                    canHideFromSearch: true, canRevealInFinder: false, canDragOut: false,
                    isSymbolIcon: true, rankPriority: 3)
            }
        }
    }

    struct KindDescriptor: Sendable {
        let label: String
        let sectionTitle: String
        let openVerb: String
        let canHideFromSearch: Bool
        let canRevealInFinder: Bool
        let canDragOut: Bool
        let isSymbolIcon: Bool
        let rankPriority: Int
    }

    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    let kind: Kind
    var primaryInstallationID: String?
    var settingsOwner: SettingsTab?
    var subtitle: String?
    var alternateTitles: [String] = []
    var symbolName: String?
    var keywords: [String] = []
    var iconStamp: Int = 0
    var iconOverride: EntryIcon?
    var installedAt: Date?
    var search = SearchProfile.unnamed

    var preferenceKey: String { bundleID ?? id }

    var isPrimaryInstallation: Bool { primaryInstallationID == nil || primaryInstallationID == id }

    var naming: EntryNaming.Sources {
        var sources = EntryNaming.Sources(name: name)
        sources.alternateTitles = alternateTitles
        sources.subtitle = subtitle
        sources.keywords = keywords
        return sources
    }

    mutating func buildSearchProfile() { search = EntryNaming.profile(for: naming) }

    mutating func addAlternateTitle(_ candidate: String) {
        let existing = [name] + alternateTitles
        guard !candidate.isEmpty,
            !existing.contains(where: {
                FuzzyMatch.normalized($0) == FuzzyMatch.normalized(candidate)
            })
        else { return }
        alternateTitles.append(candidate)
    }

    var kindLabel: String { kind.descriptor.label }

    var hotKeyAction: HotKeyAction? {
        switch kind {
        case .command:
            return CommandCatalog.command(for: self)?.hotKeyAction
        case .application:
            return bundleID.map { .app(bundleID: $0) }
        case .systemSettings:
            return bundleID.map { .settingsPane(bundleID: $0) }
        case .customCommand:
            return CustomCommand.id(fromEntryID: id).map { .customCommand(id: $0) }
        case .systemAction:
            return SystemActionCatalog.action(forEntryID: id).map { .systemAction(id: $0.id) }
        case .windowCommand:
            if let command = WindowCommandCatalog.command(forEntryID: id) {
                return .windowCommand(id: command.id)
            }
            return CustomWindowSize.id(fromEntryID: id).map { .customWindowSize(id: $0) }
        case .windowLayout:
            return WindowLayout.id(fromEntryID: id).map { .windowLayout(id: $0) }
        case .windowRoom:
            return Room.id(fromEntryID: id).map { .windowRoom(id: $0) }
        }
    }

    var canRevealInFinder: Bool { kind.descriptor.canRevealInFinder }

    var canHideFromSearch: Bool { kind.descriptor.canHideFromSearch }

    var canDragOut: Bool { kind.descriptor.canDragOut }

    var iconSource: EntryIcon { iconOverride ?? defaultIcon }

    private var defaultIcon: EntryIcon {
        guard kind.descriptor.isSymbolIcon else { return .file(stamp: iconStamp) }
        return .symbol(symbolName ?? kindSymbol)
    }

    private var kindSymbol: String {
        switch kind {
        case .customCommand: return CustomCommand.sfSymbol
        case .command: return CommandCatalog.command(for: self)?.sfSymbol ?? "questionmark"
        case .systemAction: return SystemActionCatalog.action(forEntryID: id)?.sfSymbol ?? "questionmark"
        case .windowCommand:
            return WindowCommandCatalog.command(forEntryID: id)?.sfSymbol
                ?? CustomWindowSize.sfSymbol
        case .windowLayout: return WindowLayout.sfSymbol
        case .windowRoom: return Room.sfSymbol
        case .application, .systemSettings: return "questionmark"
        }
    }

    @MainActor var icon: NSImage {
        IconCache.observeStyle()
        return IconCache.icon(for: iconSource, fileURL: url)
    }

    var iconKey: String { "\(id)|\(iconSource)" }
}

extension AppEntry {
    init(_ layout: WindowLayout) {
        self.init(
            id: layout.entryID, name: layout.name,
            url: URL(string: "nanocast://window-layout/" + layout.id.uuidString)!,
            bundleID: nil, kind: .windowLayout, symbolName: layout.iconSymbol)
    }

    init(_ room: Room) {
        self.init(
            id: room.entryID, name: room.name,
            url: URL(string: "nanocast://window-room/" + room.id.uuidString)!,
            bundleID: nil, kind: .windowRoom)
    }

    init(_ command: WindowCommand) {
        self.init(
            id: command.entryID, name: command.name,
            url: URL(string: "nanocast://window-command/" + command.id.rawValue)!,
            bundleID: nil, kind: .windowCommand)
    }

    init(_ size: CustomWindowSize) {
        self.init(
            id: size.entryID, name: size.name,
            url: URL(string: "nanocast://window-size/" + size.id.uuidString)!,
            bundleID: nil, kind: .windowCommand)
    }

    init(_ command: CustomCommand) {
        self.init(
            id: command.entryID, name: command.name,
            url: URL(string: "nanocast://custom-command/" + command.id.uuidString)!,
            bundleID: nil, kind: .customCommand, symbolName: command.iconSymbol)
    }

}

extension AppEntry.Kind {
    private static let byCategoryName: [String: AppEntry.Kind] = allCases.reduce(into: [:]) { table, kind in
        for name in kind.categoryNames { table[FuzzyMatch.normalized(name)] = kind }
    }

    private static let categoryCandidates = allCases.map { kind in
        (kind, kind.categoryNames.map(FuzzyMatch.Candidate.init))
    }

    private var categoryNames: [String] { [descriptor.sectionTitle, descriptor.label] }

    static func named(by query: LauncherOrder.CategoryQuery) -> AppEntry.Kind? {
        byCategoryName[query.name]
    }

    static func matching(by query: LauncherOrder.CategoryQuery) -> Set<AppEntry.Kind> {
        if let kind = named(by: query) { return [kind] }
        return Set(
            categoryCandidates.compactMap { kind, names in
                names.contains(where: query.matches) ? kind : nil
            })
    }
}

@MainActor
@Observable
final class AppIndex {
    private(set) var apps: [AppEntry] = []
    private var searchEntries: [AppEntry] = []

    struct Results: Equatable {
        var entries: [AppEntry] = []
        var favoriteCount = 0
        var suggestionCount = 0
        var matchCount = 0
    }

    private struct MatchKey: Equatable {
        let query: String
        let limit: Int
        let entriesRevision: Int
        let rankingRevision: Int
        let aliasRevision: Int
        let sensitivity: SearchSensitivity
    }

    private struct ResultsKey: Equatable {
        let match: MatchKey
        let visibilityRevision: Int
        let favoritesRevision: Int
        let hotKeysRevision: Int
        let showsSuggestions: Bool
        let minute: Int
    }

    @ObservationIgnored private var matchMemo = Memo<MatchKey, Results>()
    @ObservationIgnored private var resultsMemo = Memo<ResultsKey, Results>()
    private var entriesRevision = 0

    private static let systemActionEntries: [AppEntry] = SystemActionCatalog.all
        .map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "nanocast://system-action/" + command.id.rawValue)!,
                bundleID: nil, kind: .systemAction)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private static let allWindowCommandEntries: [AppEntry] = WindowCommandCatalog.all
        .map(AppEntry.init)
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private var discoveredEntries: [AppEntry] = []
    private var customCommandEntries: [AppEntry] = []
    private var windowCommandEntries: [AppEntry] = []
    private var customWindowSizeEntries: [AppEntry] = []
    private var windowLayoutEntries: [AppEntry] = []
    private var windowRoomEntries: [AppEntry] = []
    private var hiddenCommands: Set<CommandID> = []
    private var unlistedCommands: Set<CommandID> = []
    private var nameCache = BundleNameCache()
    private var paneCache: SettingsPaneScanner.Cache?
    private var isRefreshing = false
    private var refreshPending = false
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private var settings: AppSettings?
    @ObservationIgnored var onScan: (() -> Void)?

    init(ranking: LauncherRankingStore, aliases: AliasStore) {
        self.ranking = ranking
        self.aliases = aliases
    }

    private var commandEntries: [AppEntry] {
        visibleCatalogEntries.filter { $0.kind == .command }
    }

    private var visibleCatalogEntries: [AppEntry] {
        CommandCatalog.all.filter {
            guard let command = CommandCatalog.command(for: $0) else { return true }
            return !hiddenCommands.contains(command) && !unlistedCommands.contains(command)
        }
    }

    func isCommandEnabled(_ command: CommandID) -> Bool {
        !hiddenCommands.contains(command)
    }

    func setCommandsVisible(_ commands: Set<CommandID>, _ visible: Bool) {
        let updated = visible ? hiddenCommands.subtracting(commands) : hiddenCommands.union(commands)
        guard updated != hiddenCommands else { return }
        hiddenCommands = updated
        publishEntries()
    }

    func setCommandsListed(_ commands: Set<CommandID>, _ listed: Bool) {
        let updated =
            listed ? unlistedCommands.subtracting(commands) : unlistedCommands.union(commands)
        guard updated != unlistedCommands else { return }
        unlistedCommands = updated
        publishEntries()
    }

    func setCustomCommands(_ commands: [CustomCommand]) {
        let entries = commands.filter { $0.isEnabled && $0.showsInRootSearch }.map(AppEntry.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != customCommandEntries else { return }
        customCommandEntries = entries
        publishEntries()
    }

    func setWindowCommandsVisible(_ visible: Bool) {
        let entries = visible ? Self.allWindowCommandEntries : []
        guard entries != windowCommandEntries else { return }
        windowCommandEntries = entries
        publishEntries()
    }

    func setCustomWindowSizes(_ sizes: [CustomWindowSize]) {
        let entries = sizes.sorted(by: CustomWindowSize.precedes).map(AppEntry.init)
        guard entries != customWindowSizeEntries else { return }
        customWindowSizeEntries = entries
        publishEntries()
    }

    func setWindowLayouts(_ layouts: [WindowLayout]) {
        let entries = layouts.sorted(by: WindowLayout.precedes).map(AppEntry.init)
        guard entries != windowLayoutEntries else { return }
        windowLayoutEntries = entries
        publishEntries()
    }

    func setWindowRooms(_ rooms: [Room]) {
        let entries = rooms.sorted(by: Room.precedes).map(AppEntry.init)
        guard entries != windowRoomEntries else { return }
        windowRoomEntries = entries
        publishEntries()
    }

    func start(settings: AppSettings) {
        self.settings = settings
        observeSearchScopes()
    }

    private func observeSearchScopes() {
        withObservationTracking {
            _ = settings?.searchScopes
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeSearchScopes()
                await self.refresh()
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            let scopes = settings?.searchScopes ?? SearchScopes.defaults
            let reusingPanes = paneCache
            let reusing = BundleNameCache(reusing: nameCache)
            let (found, cache, panes) = await Task.detached(priority: .utility) {
                AppIndex.scan(scopes: scopes, cache: reusing, paneCache: reusingPanes)
            }.value
            nameCache = cache
            paneCache = panes
            guard found != discoveredEntries else { continue }
            discoveredEntries = found
            publishEntries()
        } while refreshPending
        onScan?()
    }

    func isUninstalled(bundleID: String) -> Bool {
        !discoveredEntries.contains { $0.kind == .application && $0.bundleID == bundleID }
            && NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil
    }

    nonisolated private static func scan(
        scopes: [String], cache: BundleNameCache,
        paneCache: SettingsPaneScanner.Cache?
    ) -> ([AppEntry], BundleNameCache, SettingsPaneScanner.Cache?) {
        Signposts.interval("AppIndex.scan") {
            var cache = cache
            var indexByBundleID: [String: Int] = [:]
            var paths = Set<String>()
            var result: [AppEntry] = []
            for url in SearchScopes.appBundles(in: scopes) {
                let path = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard paths.insert(path).inserted else { continue }
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier
                let fileName = EntryNaming.strippingAppExtension(url.lastPathComponent)
                // Finder's rule: LaunchServices ignores a display name the file name contradicts.
                let names = cache.names(
                    for: url, base: fileName, developmentRegion: bundle?.developmentLocalization)
                // Raw: a localized strings file can swap this array for a plain name.
                let alternates = bundle?.infoDictionary?["CFBundleAlternateNames"] as? [String] ?? []
                let declared = (bundle?.infoDictionary).flatMap(AppDisplayName.inInfo)
                var entry = AppEntry(
                    id: path, name: names.first ?? fileName, url: url, bundleID: bundleID,
                    kind: .application,
                    subtitle: AppDisplayName.named(bundle?.infoDictionary?["CFBundleShortVersionString"]),
                    alternateTitles: Array(names.dropFirst()) + alternates,
                    keywords: declared.map { [$0] } ?? [], iconStamp: FileIconStamp.value(for: url),
                    installedAt: try? url.resourceValues(forKeys: [.addedToDirectoryDateKey])
                        .addedToDirectoryDate)
                entry.addAlternateTitle(fileName)
                if let bundleID {
                    if let first = indexByBundleID[bundleID] {
                        entry.primaryInstallationID = result[first].id
                        result[first].primaryInstallationID = result[first].id
                    } else {
                        indexByBundleID[bundleID] = result.count
                    }
                }
                result.append(entry)
            }
            let byName = Dictionary(grouping: result.indices) { FuzzyMatch.normalized(result[$0].name) }
            for group in byName.values {
                let byVersion = Dictionary(grouping: group) { result[$0].subtitle ?? "" }
                for index in group {
                    guard group.count > 1 || result[index].primaryInstallationID != nil else {
                        result[index].subtitle = nil
                        continue
                    }
                    if result[index].subtitle == nil
                        || (byVersion[result[index].subtitle ?? ""]?.count ?? 0) > 1
                    {
                        let folder = SearchScopes.abbreviate(
                            result[index].url.deletingLastPathComponent().path)
                        result[index].subtitle = [result[index].subtitle, folder].compactMap { $0 }
                            .joined(separator: " · ")
                    }
                }
            }
            let apps = result.sorted {
                let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                if $0.isPrimaryInstallation != $1.isPrimaryInstallation { return $0.isPrimaryInstallation }
                return $0.id < $1.id
            }
            let (panes, panesCache) = SettingsPaneScanner.scan(cache: paneCache)
            return (AppIndex.named(apps + panes), cache, panesCache)
        }
    }

    nonisolated private static func named(_ entries: [AppEntry]) -> [AppEntry] {
        entries.map { entry in
            var entry = entry
            entry.buildSearchProfile()
            return entry
        }
    }

    private func publishEntries() {
        let updated =
            discoveredEntries
            + Self.named(
                Self.systemActionEntries + windowLayoutEntries + windowRoomEntries
                    + windowCommandEntries
                    + customWindowSizeEntries + customCommandEntries
                    + commandEntries)
        guard updated != searchEntries else { return }
        searchEntries = updated
        apps = updated.filter(\.isPrimaryInstallation)
        entriesRevision &+= 1
    }

    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let matched = searchResults(query, limit: limit).entries
        guard matched.contains(where: { !$0.isPrimaryInstallation }) else { return matched }
        let primary = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        var seen = Set<String>()
        return matched.compactMap { entry in
            let representative = entry.primaryInstallationID.flatMap { primary[$0] } ?? entry
            return seen.insert(representative.id).inserted ? representative : nil
        }
    }

    private func searchResults(_ query: String, limit: Int = 200) -> Results {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Results(entries: searchEntries) }
        return matchMemo.value(for: matchKey(q, limit: limit)) {
            let category = LauncherOrder.CategoryQuery(q)
            if let kind = AppEntry.Kind.named(by: category) {
                return Results(entries: categoryListing(kind, query: category.name))
            }
            let ranked = rank(q, limit: limit)
            let listed = categoryRemainder(AppEntry.Kind.matching(by: category), excluding: ranked)
            return Results(entries: ranked + listed, matchCount: ranked.count)
        }
    }

    private func categoryListing(_ kind: AppEntry.Kind, query: String) -> [AppEntry] {
        let listed = searchEntries.filter {
            $0.kind == kind || FuzzyMatch.normalized($0.name) == query
        }
        return byUsage(listed, usage: ranking.snapshot())
    }

    private func categoryRemainder(
        _ kinds: Set<AppEntry.Kind>, excluding ranked: [AppEntry]
    ) -> [AppEntry] {
        guard !kinds.isEmpty else { return [] }
        let matched = Set(ranked.map(\.id))
        let listed = searchEntries.filter { kinds.contains($0.kind) && !matched.contains($0.id) }
        return byUsage(listed, usage: ranking.snapshot())
    }

    func orderedResults(
        query: String, visibility: VisibilityStore, favorites: FavoritesStore, hotKeys: HotKeyManager
    ) -> Results {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let showsSuggestions = settings?.launcherShowsSuggestions ?? true
        let usage = ranking.snapshot()
        let key = ResultsKey(
            match: matchKey(q, limit: 200), visibilityRevision: visibility.revision,
            favoritesRevision: favorites.revision, hotKeysRevision: hotKeys.revision,
            showsSuggestions: showsSuggestions, minute: Int(usage.now.timeIntervalSince1970 / 60))
        return resultsMemo.value(for: key) {
            let matched = searchResults(q)
            let visible = matched.entries.filter(visibility.isVisible)
            guard q.isEmpty else {
                let matchCount = matched.entries.prefix(matched.matchCount).count(where: visibility.isVisible)
                return Results(entries: visible, matchCount: matchCount)
            }
            let split = favorites.ordered(visible.filter(\.isPrimaryInstallation))
            let suggested =
                showsSuggestions ? suggestions(from: split.rest, usage: usage, hotKeys: hotKeys) : []
            let shown = Set((split.favorites + suggested).map(\.id))
            let rest = byUsage(visible.filter { !shown.contains($0.id) }, usage: usage)
            return Results(
                entries: split.favorites + suggested + rest,
                favoriteCount: split.favorites.count, suggestionCount: suggested.count)
        }
    }

    private var sensitivity: SearchSensitivity { settings?.rootSearchSensitivity ?? .default }

    private func matchKey(_ query: String, limit: Int) -> MatchKey {
        MatchKey(
            query: query, limit: limit, entriesRevision: entriesRevision, rankingRevision: ranking.revision,
            aliasRevision: aliases.revision, sensitivity: sensitivity)
    }

    private func rank(_ q: String, limit: Int) -> [AppEntry] {
        Signposts.interval("AppIndex.rank") {
            let usage = ranking.snapshot()
            return LauncherOrder.ranked(
                searchEntries, query: LauncherOrder.Query(q), sensitivity: sensitivity, limit: limit,
                profile: \.search, signals: { self.signals(for: $0, usage: usage) })
        }
    }

    private func byUsage(_ entries: [AppEntry], usage: LauncherRankingStore.Snapshot) -> [AppEntry] {
        var ordered: [AppEntry] = []
        ordered.reserveCapacity(entries.count)
        var start = entries.startIndex
        while start < entries.endIndex {
            let kind = entries[start].kind
            let end = entries[start...].firstIndex { $0.kind != kind } ?? entries.endIndex
            ordered += LauncherOrder.byUsage(
                Array(entries[start..<end]), signals: { self.signals(for: $0, usage: usage) })
            start = end
        }
        return ordered
    }

    private func suggestions(
        from entries: [AppEntry], usage: LauncherRankingStore.Snapshot, hotKeys: HotKeyManager
    ) -> [AppEntry] {
        let eligible = entries.filter { !($0.bundleID?.hasPrefix(Self.ownBundlePrefix) ?? false) }
        return LauncherSuggestions.select(from: eligible, now: usage.now) { entry in
            LauncherSuggestions.Traits(
                signals: signals(for: entry, usage: usage), installedAt: entry.installedAt,
                hasHotKey: entry.hotKeyAction.flatMap(hotKeys.binding(for:)) != nil,
                priority: CommandCatalog.command(for: entry)?.suggestionPriority)
        }
    }

    private static let ownBundlePrefix = "com.nanocast."

    private func signals(
        for entry: AppEntry, usage: LauncherRankingStore.Snapshot
    ) -> LauncherOrder.Signals {
        LauncherOrder.Signals(
            alias: aliases.alias(for: entry.preferenceKey).map { SearchText($0, transliterated: false) },
            usage: usage.usage(for: entry.preferenceKey),
            priority: entry.kind.descriptor.rankPriority, title: entry.name)
    }
}
