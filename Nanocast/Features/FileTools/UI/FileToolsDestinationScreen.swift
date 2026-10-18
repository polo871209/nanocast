import SwiftUI

struct FileToolsDestinationScreen: PaletteScreen {
    let search: FileSearchSession
    let core: AppCore
    let vm: PaletteState

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    var rows: [FileSearchResult] { search.results.filter(\.isDirectory) }

    private func folder(at selection: Int) -> FileSearchResult? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func hasActions(at selection: Int) -> Bool { false }

    func activate(at selection: Int) {
        guard let folder = folder(at: selection) else { return }
        core.fileToolsCoordinator.transfer(into: folder)
    }

    func secondary(at selection: Int) -> Bool {
        guard let folder = folder(at: selection) else { return false }
        core.fileSearchCoordinator.showInFinder(folder)
        return true
    }

    func tab(at selection: Int, backwards: Bool) -> Bool { true }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            if search.state == .ready {
                EmptyResults(text: "No matching folders", systemImage: "folder")
            } else {
                Color.clear
            }
        } else {
            let selected = folder(at: selection)
            HStack(spacing: 0) {
                FileSearchList(
                    title: core.fileToolsCoordinator.destinationTitle,
                    results: rows,
                    selectedID: selected?.id,
                    scroll: scroll,
                    onSelect: { folder in vm.selection = rows.firstIndex(of: folder) ?? 0 },
                    onActivate: { core.fileToolsCoordinator.transfer(into: $0) },
                    onActions: { _ in },
                    onDropped: { core.paletteCoordinator.dragLanded() }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: Theme.Size.hairline)
                FileSearchPreview(result: selected)
            }
        }
    }
}
