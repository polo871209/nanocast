import AVFoundation

enum ScreenRecordingFormat: String, CaseIterable, Identifiable, Sendable {
    case mov
    case mp4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mov: "MOV"
        case .mp4: "MP4"
        }
    }

    var fileExtension: String { rawValue }

    var fileType: AVFileType {
        switch self {
        case .mov: .mov
        case .mp4: .mp4
        }
    }
}
