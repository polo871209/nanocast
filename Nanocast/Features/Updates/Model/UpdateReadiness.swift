import Foundation

struct UpdateActivity: Sendable {
    var isInsertingText = false
    var isUninstalling = false
    var isRecordingHotKey = false
    var isShowingDialog = false
    var isPaletteVisible = false
}

enum UpdateReadiness {
    enum Blocker: Equatable, Sendable {
        case insertingText
        case uninstalling
        case recordingHotKey
        case dialogOpen
        case paletteOpen

        var message: String {
            switch self {
            case .insertingText:
                return String(localized: "Waiting for dictated text to finish inserting.")
            case .uninstalling: return String(localized: "Waiting for the uninstaller to finish.")
            case .recordingHotKey: return String(localized: "Finish recording the shortcut first.")
            case .dialogOpen: return String(localized: "Close the open dialog first.")
            case .paletteOpen: return String(localized: "Close Nanocast's window first.")
            }
        }
    }

    static func evaluate(_ activity: UpdateActivity) -> Blocker? {
        if activity.isInsertingText { return .insertingText }
        if activity.isUninstalling { return .uninstalling }
        if activity.isRecordingHotKey { return .recordingHotKey }
        if activity.isShowingDialog { return .dialogOpen }
        if activity.isPaletteVisible { return .paletteOpen }
        return nil
    }
}
