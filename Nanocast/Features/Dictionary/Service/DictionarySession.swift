import Foundation

@MainActor
@Observable
final class DictionarySession {
    struct Lookup: Equatable {
        let term: String
        let entry: DictionaryEntry?
    }

    private(set) var lookup: Lookup?
    @ObservationIgnored private var term = ""
    @ObservationIgnored private var task: Task<Void, Never>?

    private static let debounce = Duration.milliseconds(90)

    func lookUp(_ query: String) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term != self.term else { return }
        self.term = term
        task?.cancel()
        guard !term.isEmpty else {
            lookup = nil
            return
        }
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            let entry = await Task.detached(priority: .userInitiated) {
                DictionaryService.entry(for: term)
            }.value
            guard !Task.isCancelled else { return }
            self?.lookup = Lookup(term: term, entry: entry)
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        term = ""
        lookup = nil
    }
}
