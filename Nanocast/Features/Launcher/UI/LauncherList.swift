import SwiftUI

struct LauncherList: View {

    @Environment(\.metrics) private var metrics
    let results: [AppEntry]
    let selectedRowID: String?
    let favoriteCount: Int
    let suggestionCount: Int
    let matchCount: Int
    let scroll: ScrollIntent
    var card: LeadCard?
    var cardSelected = false
    var onActivateCard: () -> Void = {}
    var onCardActions: () -> Void = {}
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    let onDropped: () -> Void
    var files: FileSection?
    @Environment(RunningAppsMonitor.self) private var runningApps

    struct FileSection {
        let results: [FileSearchResult]
        let onActivate: (Int) -> Void
        let onActions: (Int) -> Void
    }

    enum LeadCard: Equatable {
        case calc(CalcResult)
        case color(ColorValue)

        var sectionTitle: String {
            switch self {
            case .calc: return String(localized: "Calculator")
            case .color: return String(localized: "Color")
            }
        }

        var rowID: String {
            switch self {
            case .calc: return "calc-card"
            case .color: return "color-card"
            }
        }
    }

    private enum Row: Identifiable {
        case header(String)
        case card(LeadCard)
        case app(AppEntry, slot: Character?)
        case file(FileSearchResult, index: Int)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .card(let card): return card.rowID
            case .app(let app, _): return app.id
            case .file(let result, _): return "file-" + result.id
            }
        }
    }

    private var firstRowSelected: Bool {
        card != nil ? cardSelected : selectedRowID != nil && selectedRowID == results.first?.id
    }

    private var fileRows: [Row] {
        guard let files else { return [] }
        return [.header(String(localized: "Files"))]
            + files.results.enumerated().map { Row.file($1, index: $0) }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let card { rows = [.header(card.sectionTitle), .card(card)] }
        let favorites = results.prefix(favoriteCount)
        let suggestions = results.dropFirst(favoriteCount).prefix(suggestionCount)
        let pinnedCount = favoriteCount + suggestionCount
        let matches = results.dropFirst(pinnedCount).prefix(matchCount)
        let rest = results.dropFirst(pinnedCount + matchCount)
        var grouped: [AppEntry.Kind: [AppEntry]] = [:]
        for app in rest { grouped[app.kind, default: []].append(app) }
        if !favorites.isEmpty {
            rows.append(.header(String(localized: "Favorites")))
            rows.append(
                contentsOf: favorites.enumerated().map {
                    .app($1, slot: FavoriteSlots.digit(at: $0))
                })
        }
        if !suggestions.isEmpty {
            rows.append(.header(String(localized: "Suggestions")))
            rows.append(contentsOf: suggestions.map { .app($0, slot: nil) })
        }
        if !matches.isEmpty {
            rows.append(.header(String(localized: "Results")))
            rows.append(contentsOf: matches.map { .app($0, slot: nil) })
        }
        let kinds: [AppEntry.Kind] = [
            .application, .systemSettings, .systemAction, .windowLayout, .windowRoom,
            .windowCommand, .customCommand, .command
        ]
        for kind in kinds {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            rows.append(.header(kind.descriptor.sectionTitle.resolved()))
            rows.append(contentsOf: group.map { .app($0, slot: nil) })
        }
        assert(
            grouped.keys.allSatisfy(kinds.contains),
            "kind missing from the launcher's section order: "
                + grouped.keys.filter { !kinds.contains($0) }.map(\.rawValue).joined(separator: ", "))
        return rows + fileRows
    }

    var body: some View {
        let rows = rows
        return Group {
            if results.isEmpty && card == nil && files == nil {
                EmptyResults(text: String(localized: "No apps found"))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                switch row {
                                case .header(let title):
                                    SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                                case .card(let card):
                                    LeadCardView(card: card, selected: cardSelected)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onActivateCard)
                                        .onRightClick(perform: onCardActions)
                                        .padding(.bottom, metrics.spacing.xs)
                                        .selectionFrame(cardSelected)
                                case .app(let app, let slot):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedRowID,
                                        running: runningApps.isRunning(app),
                                        slot: slot
                                    )
                                    .contentShape(Rectangle())
                                    .onRowTap(drag: drag(for: app)) { onActivate(app) }
                                    .onRightClick { onActions(app) }
                                    .selectionFrame(app.id == selectedRowID)
                                case .file(let result, let index):
                                    FileSearchRow(
                                        result: result, selected: row.id == selectedRowID,
                                        showsLocation: true
                                    )
                                    .contentShape(Rectangle())
                                    .onRowTap(drag: result.rowDrag(dropped: onDropped)) {
                                        files?.onActivate(index)
                                    }
                                    .onRightClick { files?.onActions(index) }
                                    .selectionFrame(row.id == selectedRowID)
                                }
                            }
                        }
                        .padding(.horizontal, metrics.spacing.md)
                        .padding(.top, metrics.spacing.xs)
                        .padding(.bottom, metrics.spacing.md)
                        .hideNativeScrollers()
                        .scrollOriginAnchor()
                    }
                    .edgeDissolve()
                    .thinScrollbar()
                    .scrollFollowsSelection(
                        scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
                }
            }
        }
    }

    private func drag(for app: AppEntry) -> RowDrag? {
        guard app.canDragOut else { return nil }
        return RowDrag(
            item: { .file(app.url, image: IconCache.cached(app.iconSource, fileURL: app.url)) },
            dropped: onDropped)
    }
}

private struct LeadCardView: View {
    let card: LauncherList.LeadCard
    let selected: Bool

    var body: some View {
        switch card {
        case .calc(let result):
            CalculatorCard(result: result, selected: selected)
        case .color(let color):
            ColorCard(color: color, selected: selected)
        }
    }
}

private struct AppRow: View {

    @Environment(\.metrics) private var metrics
    let app: AppEntry
    let selected: Bool
    let running: Bool
    let slot: Character?
    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(AliasStore.self) private var aliases
    @Environment(PaletteState.self) private var palette
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var shortcutCaps: [String]? {
        guard let action = app.hotKeyAction else { return nil }
        return hotKeys.binding(for: action)?.keycaps
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            AppIconView(app: app, pointSize: metrics.size.resultRowIcon)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 3, height: 3)
                            .offset(y: 3)
                    }
                }
            Text(app.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            if let subtitle = app.subtitle {
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let alias = aliases.alias(for: app.preferenceKey) {
                Text(alias)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, metrics.spacing.sm)
                    .padding(.vertical, metrics.spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                            .fill(Theme.Colors.controlSurface))
            }
            if let caps = shortcutCaps {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
            Spacer()
            if let slot, palette.commandHeld {
                HStack(spacing: metrics.spacing.xxs) {
                    KeyCapChip(text: "⌘", style: .outline)
                    KeyCapChip(text: String(slot), style: .outline)
                }
            } else {
                Text(app.kindLabel)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}
