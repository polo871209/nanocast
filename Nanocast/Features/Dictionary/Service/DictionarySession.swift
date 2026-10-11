import Foundation

@MainActor
@Observable
final class DictionarySession {
    struct Lookup: Equatable {
        let term: String
        let scope: DictionaryScope
        let entry: DictionaryEntry?
    }

    private(set) var lookup: Lookup?
    private(set) var scope = DictionaryScope.dictionary
    private(set) var hasThesaurus = false
    @ObservationIgnored private var term = ""
    @ObservationIgnored private var task: Task<Void, Never>?

    private static let debounce = Duration.milliseconds(90)

    /// Dictionary.app's list can change between visits, so each one reads it afresh.
    func refreshScopes() {
        hasThesaurus = DictionaryService.hasThesaurus()
        if !hasThesaurus { scope = .dictionary }
    }

    func select(_ scope: DictionaryScope) {
        guard scope != self.scope else { return }
        self.scope = scope
        let query = term
        term = ""
        lookUp(query)
    }

    func lookUp(_ query: String) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term != self.term else { return }
        self.term = term
        task?.cancel()
        guard !term.isEmpty else {
            lookup = nil
            return
        }
        let scope = scope
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            let entry = await Task.detached(priority: .userInitiated) {
                DictionaryService.entry(for: term, in: scope)
            }.value
            guard !Task.isCancelled else { return }
            self?.lookup = Lookup(term: term, scope: scope, entry: entry)
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        term = ""
        lookup = nil
    }
}
