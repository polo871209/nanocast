struct ScreenRecordingOptions: Sendable, Equatable {
    var capturesSystemAudio = false
    var microphone: Microphone?
    var showsClicks = false

    enum Microphone: Sendable, Equatable {
        case systemDefault
        case device(id: String)
    }
}
