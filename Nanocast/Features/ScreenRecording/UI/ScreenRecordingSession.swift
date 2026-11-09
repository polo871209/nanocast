import Foundation
import Observation

@MainActor
@Observable
final class ScreenRecordingSession {
    enum Status: Equatable {
        case ready
        case starting
        case recording(since: Date)
        case paused(recorded: TimeInterval)
        case saving
    }

    var status: Status

    init(status: Status) {
        self.status = status
    }
}
