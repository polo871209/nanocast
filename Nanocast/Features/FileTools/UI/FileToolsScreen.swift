import SwiftUI

struct FileToolsScreen: PaletteScreen {
    let session: FileToolsSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    private var coordinator: FileToolsCoordinator { core.fileToolsCoordinator }

    private var query: ActionMenuSearchQuery { ActionMenuSearchQuery(vm.query) }

    var rows: [FileTool] {
        let query = query
        return session.tools.filter { query.score($0.searchText) != nil }
    }

    var landingSelection: Int {
        let query = query
        guard !query.isEmpty else { return 0 }
        let scored = rows.enumerated().compactMap { index, tool in
            query.score(tool.searchText).map { (index, $0) }
        }
        return scored.max { $0.1 < $1.1 }?.0 ?? 0
    }

    private func tool(at selection: Int) -> FileTool? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    private var singleFile: FileSearchResult? {
        guard let subject = session.subject, !subject.isBatch, let item = subject.first else { return nil }
        return coordinator.searchResult(for: item)
    }

    func hasActions(at selection: Int) -> Bool { session.subject != nil }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let subject = session.subject else { return nil }
        let file = singleFile
        var items = session.tools
            .filter { $0.section == .actions && !(file != nil && $0.kind == .copyPath) }
            .map { tool in
                PopoverMenuItem(
                    title: tool.title, systemImage: tool.systemImage,
                    shortcut: tool.kind == .copyPath ? "⌃⌘C" : nil
                ) { coordinator.run(tool, fields: [:]) }
            }
        if let file {
            var fileItems = FileSearchActionsMenu.content(result: file, core: core, offersFileTools: false).items
            if !items.isEmpty, !fileItems.isEmpty { fileItems[0].startsSection = true }
            items += fileItems
        } else {
            items.append(
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "folder", startsSection: !items.isEmpty,
                    shortcut: "⌘↵"
                ) { coordinator.showSubjectInFinder() })
        }
        return PopoverMenuContent(header: file?.name ?? "\(subject.items.count) files", items: items)
    }

    func activate(at selection: Int) {
        guard let tool = tool(at: selection) else { return }
        coordinator.run(tool, fields: fieldValues(for: tool))
    }

    func secondary(at selection: Int) -> Bool {
        guard session.subject != nil else { return false }
        coordinator.showSubjectInFinder()
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if shortcut == .copyPath, session.subject != nil {
            coordinator.copyPaths()
            return true
        }
        guard let file = singleFile else { return false }
        return FileSearchActionsMenu.perform(shortcut, result: file, core: core)
    }

    func tab(at selection: Int, backwards: Bool) -> Bool {
        guard let tool = tool(at: selection) else { return true }
        guard tool.fields.isEmpty else { return false }
        coordinator.cycleOption(of: tool, backwards: backwards)
        return true
    }

    func headerAccessory(at selection: Int, focus: FocusState<String?>.Binding) -> PaletteHeaderAccessory? {
        guard let tool = tool(at: selection), !tool.fields.isEmpty else { return nil }
        let arguments = tool.fields.map {
            InlineArgument(id: $0.rawValue, title: $0.title, isOptional: $0.isOptional)
        }
        let value = { (id: String) in binding(tool: tool, id: id) }
        let firstOwed = { arguments.first { !$0.isOptional && value($0.id).wrappedValue.isEmpty }?.id }
        return PaletteHeaderAccessory(
            width: InlineArgumentFields.totalWidth(for: arguments, hasIcon: true, metrics: metrics),
            fieldNames: arguments.map(\.id),
            firstIncompleteField: firstOwed(),
            view: AnyView(
                InlineArgumentFields(
                    arguments: arguments, symbol: tool.systemImage, value: value, focused: focus,
                    openOptions: { _ in },
                    onSubmit: {
                        guard let owed = firstOwed() else { return activate(at: selection) }
                        focus.wrappedValue = owed
                    }
                )
                .id(tool.id)))
    }

    private func argumentKey(tool: FileTool, id: String) -> PaletteState.ArgumentKey {
        PaletteState.ArgumentKey(entryID: "fileTools:\(tool.id)", name: id)
    }

    private func binding(tool: FileTool, id: String) -> Binding<String> {
        let key = argumentKey(tool: tool, id: id)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }

    private func fieldValues(for tool: FileTool) -> [FileToolField: String] {
        Dictionary(
            uniqueKeysWithValues: tool.fields.map {
                ($0, vm.commandArguments[argumentKey(tool: tool, id: $0.rawValue)] ?? "")
            })
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if let subject = session.subject {
            let rows = rows
            let selected = tool(at: selection)
            HStack(spacing: 0) {
                Group {
                    if rows.isEmpty {
                        EmptyResults(
                            text: session.tools.isEmpty
                                ? "No tools for this file type"
                                : "No matching tools",
                            systemImage: session.tools.isEmpty ? "wand.and.sparkles" : "magnifyingglass")
                    } else {
                        FileToolsList(
                            tools: rows,
                            selectedID: selected?.id,
                            scroll: scroll,
                            onSelect: { tool in vm.selection = rows.firstIndex(of: tool) ?? 0 },
                            onActivate: { coordinator.run($0, fields: fieldValues(for: $0)) })
                    }
                }
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: Theme.Size.hairline)
                FileToolsPane(
                    subject: subject, file: singleFile, tool: selected,
                    option: selected.flatMap(session.option(for:)), job: session.job,
                    outcome: session.outcome,
                    onChoose: { option in
                        if let selected { coordinator.choose(option, for: selected) }
                    },
                    onRun: { if let selected { coordinator.run(selected, fields: fieldValues(for: selected)) } },
                    onCancel: { coordinator.cancelJob() })
            }
        } else {
            Color.clear
        }
    }
}
