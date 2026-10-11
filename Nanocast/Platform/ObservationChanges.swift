import Observation

/// Calls `onChange` after each change to what `read` reads, until the returned token goes away.
@MainActor
func observeChanges<Value: Equatable & Sendable>(
    of read: @escaping @Sendable @MainActor () -> Value,
    onChange: @escaping @Sendable @MainActor () -> Void
) -> ObservationTracking.Token {
    let registered = read()
    // The first event comes a turn late, so an earlier change shows only as a new value.
    return withContinuousObservation(options: .didSet) { event in
        guard read() != registered || event.kind != .initial else { return }
        onChange()
    }
}
