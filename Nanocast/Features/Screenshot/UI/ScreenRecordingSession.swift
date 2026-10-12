import Foundation
import Observation

@MainActor
@Observable
final class ScreenRecordingSession {
    enum Status: Equatable {
        case starting
        case recording(since: Date)
        case saving
    }

    var status = Status.starting
}
