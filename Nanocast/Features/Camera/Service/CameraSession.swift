import AVFoundation
import AppKit
import Synchronization

/// `AVCaptureSession` is not `Sendable`, so the blocking calls go off main behind a box.
@MainActor
final class CameraSession {
    enum Feed {
        case live(AVCaptureSession)
        case denied
        case noCamera
    }

    static var devices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    private var capture: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var device: AVCaptureDevice?
    private var pendingPhoto: PhotoCapture?

    func start() async -> Feed {
        var access = Permissions.cameraAccess()
        if access == .notDetermined {
            _ = await Permissions.requestCameraAccess()
            access = Permissions.cameraAccess()
        }
        guard access == .granted else { return .denied }
        guard let capture = capture ?? configure() else { return .noCamera }
        self.capture = capture
        guard !capture.isRunning else { return .live(capture) }
        let box = CaptureBox(session: capture)
        await Task.detached { box.session.startRunning() }.value
        return .live(capture)
    }

    func stop() {
        guard let capture else { return }
        // A reused session without an output of its own feeds a new preview layer no frames.
        self.capture = nil
        photoOutput = nil
        guard capture.isRunning else { return }
        let box = CaptureBox(session: capture)
        Task.detached { box.session.stopRunning() }
    }

    var hasMultipleDevices: Bool { Self.devices.count > 1 }

    func switchToNextDevice() async {
        let devices = Self.devices
        guard devices.count > 1, let capture, let device else { return }
        let index = devices.firstIndex(of: device) ?? devices.count - 1
        let next = devices[(index + 1) % devices.count]
        guard let input = try? AVCaptureDeviceInput(device: next) else { return }
        let box = CaptureBox(session: capture, input: input)
        await Task.detached {
            box.session.beginConfiguration()
            for existing in box.session.inputs { box.session.removeInput(existing) }
            if let input = box.input, box.session.canAddInput(input) {
                box.session.addInput(input)
            }
            box.session.commitConfiguration()
        }.value
        self.device = next
    }

    func capturePhoto(mirrored: Bool) async -> Data? {
        guard let photoOutput, capture?.isRunning == true else { return nil }
        if let connection = photoOutput.connection(with: .video),
            connection.isVideoMirroringSupported
        {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
        let capture = PhotoCapture()
        pendingPhoto = capture
        defer { pendingPhoto = nil }
        guard let encoded = await capture.take(from: photoOutput) else { return nil }
        return await Task.detached {
            NSBitmapImageRep(data: encoded)?.representation(using: .png, properties: [:])
        }.value
    }

    private func configure() -> AVCaptureSession? {
        let preferred = device?.isConnected == true ? device : AVCaptureDevice.default(for: .video)
        guard let device = preferred, let input = try? AVCaptureDeviceInput(device: device)
        else { return nil }
        let capture = AVCaptureSession()
        capture.sessionPreset = .photo
        guard capture.canAddInput(input) else { return nil }
        capture.addInput(input)
        self.device = device
        let output = AVCapturePhotoOutput()
        guard capture.canAddOutput(output) else { return capture }
        capture.addOutput(output)
        photoOutput = output
        return capture
    }
}

private struct CaptureBox: @unchecked Sendable {
    let session: AVCaptureSession
    var input: AVCaptureDeviceInput?
}

private final class PhotoCapture: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    private let continuation = Mutex<CheckedContinuation<Data?, Never>?>(nil)

    @MainActor
    func take(from output: AVCapturePhotoOutput) async -> Data? {
        await withCheckedContinuation { continuation in
            self.continuation.withLock { $0 = continuation }
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        continuation.withLock { $0.take() }?.resume(returning: data)
    }
}
