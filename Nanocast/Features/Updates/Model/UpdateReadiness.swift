import Foundation

struct UpdateActivity: Sendable {
    var isUninstalling = false
    var isRecordingHotKey = false
    var isShowingDialog = false
    var isPaletteVisible = false
}

enum UpdateReadiness {
    enum Blocker: Equatable, Sendable {
        case uninstalling
        case recordingHotKey
        case dialogOpen
        case paletteOpen

        var message: String {
            switch self {
            case .uninstalling: return "Waiting for the uninstaller to finish."
            case .recordingHotKey: return "Finish recording the shortcut first."
            case .dialogOpen: return "Close the open dialog first."
            case .paletteOpen: return "Close Nanocast's window first."
            }
        }
    }

    static func evaluate(_ activity: UpdateActivity) -> Blocker? {
        if activity.isUninstalling { return .uninstalling }
        if activity.isRecordingHotKey { return .recordingHotKey }
        if activity.isShowingDialog { return .dialogOpen }
        if activity.isPaletteVisible { return .paletteOpen }
        return nil
    }
}
