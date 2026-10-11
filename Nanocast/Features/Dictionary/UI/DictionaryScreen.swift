import SwiftUI

struct DictionaryScreen: PaletteScreen {
    let session: DictionarySession
    let core: AppCore
    let vm: PaletteState

    private var term: String { vm.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var entry: DictionaryEntry? { session.lookup?.entry }

    var rows: [DictionaryEntry] { entry.map { [$0] } ?? [] }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry else { return nil }
        return PopoverMenuContent(
            header: entry.term,
            items: [
                PopoverMenuItem(
                    title: String(localized: "Copy Definition"), systemImage: "doc.on.doc", shortcut: "↵"
                ) {
                    core.dictionaryCoordinator.copy(entry)
                },
                PopoverMenuItem(
                    title: String(localized: "Open in Dictionary"), systemImage: "book", shortcut: "⌘↵"
                ) {
                    core.dictionaryCoordinator.openInDictionary(entry)
                }
            ])
    }

    func activate(at selection: Int) {
        guard let entry else { return }
        core.dictionaryCoordinator.copy(entry)
    }

    func secondary(at selection: Int) -> Bool {
        guard let entry else { return false }
        core.dictionaryCoordinator.openInDictionary(entry)
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        if term.isEmpty { return AnyView(EmptyResults(text: String(localized: "Type a word to define"))) }
        if let entry { return AnyView(DictionaryEntryView(entry: entry)) }
        if session.lookup?.term == term {
            return AnyView(EmptyResults(text: String(localized: "No definition found")))
        }
        return AnyView(Color.clear)
    }
}
