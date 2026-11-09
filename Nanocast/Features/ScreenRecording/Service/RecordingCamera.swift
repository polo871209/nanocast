import AVFoundation

@MainActor
final class RecordingCamera {
    let session: AVCaptureSession

    private init(session: AVCaptureSession) {
        self.session = session
    }

    static func start(deviceID: String?) async -> RecordingCamera? {
        let chosen = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) }
        guard let device = chosen ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device)
        else { return nil }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        guard session.canAddInput(input) else { return nil }
        session.addInput(input)
        let box = SessionBox(session: session)
        await Task.detached { box.session.startRunning() }.value
        return RecordingCamera(session: session)
    }

    func stop() {
        let box = SessionBox(session: session)
        Task.detached { box.session.stopRunning() }
    }
}

// AVCaptureSession is safe to start and stop from any thread, but it is not marked Sendable.
private struct SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
}
