import Foundation
import Observation

@MainActor
@Observable
final class ScreenRecordingSession {
    enum Status: Equatable {
        case setup
        case starting(recorded: TimeInterval)
        case recording(since: Date)
        case paused(recorded: TimeInterval)
        case saving(recorded: TimeInterval)
    }

    var status = Status.setup
    var target: RecordingTarget
    var microphone = false
    var camera = false
    var isChangingCamera = false
    var microphoneLevel: Float = 0

    init(target: RecordingTarget) {
        self.target = target
    }

    func recorded(at date: Date) -> TimeInterval {
        switch status {
        case .setup: 0
        case .starting(let recorded), .paused(let recorded), .saving(let recorded): recorded
        case .recording(let since): date.timeIntervalSince(since)
        }
    }

    var isCapturing: Bool {
        switch status {
        case .starting, .recording: true
        case .setup, .paused, .saving: false
        }
    }
}
