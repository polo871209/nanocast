import AVFoundation
import AppKit
import os

@MainActor
@Observable
final class ScreenRecordingCoordinator {
    private static let logger = Logger(subsystem: "com.nanocast", category: "ScreenRecording")

    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var recording: ScreenRecordingController?

    init(core: AppCore) {
        self.core = core
    }

    var saveFolder: URL {
        SaveFolder.url(for: core.settings.screenRecordingSaveFolder)
    }

    func toggle() {
        if let recording { return recording.stop(keeping: true) }
        let settings = core.settings
        let choices = RecordingChoices(
            camera: settings.screenRecordingCamera, microphone: settings.screenRecordingMicrophone)
        core.screenshotCoordinator.pickRecordingArea(with: choices) { [weak self] pick in
            settings.screenRecordingCamera = pick.choices.camera
            settings.screenRecordingMicrophone = pick.choices.microphone
            Task { await self?.record(pick) }
        }
    }

    var microphones: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
            .devices
    }

    func stopRecording() async {
        await recording?.stopAndWait()
    }

    func chooseSaveFolder() {
        guard
            let url = FolderPicker.choose(
                message: "Choose the folder screen recordings are saved in.", startingAt: saveFolder)
        else { return }
        core.settings.screenRecordingSaveFolder = SaveFolder.setting(for: url)
    }

    func resetSaveFolder() {
        core.settings.screenRecordingSaveFolder = nil
    }

    private func record(_ pick: RecordingPick) async {
        guard !pick.area.trimmedToEven.isEmpty else { return }
        let options = await options(for: pick)
        let camera = await camera(for: pick)
        guard recording == nil else {
            camera?.stop()
            return
        }
        let source = Self.source(of: pick, withCamera: camera != nil)
        let controller = ScreenRecordingController(
            source, with: options, camera: camera, area: pick.display.points(pick.area), on: pick.display,
            showsBorder: pick.window == nil || camera != nil, metrics: core.settings.interfaceSize.metrics
        ) { [weak self] outcome in
            self?.finish(outcome)
        }
        recording = controller
        controller.start(savingIn: saveFolder, as: core.settings.screenRecordingFormat)
    }

    private static func source(of pick: RecordingPick, withCamera: Bool) -> ScreenRecordingRunner.Source {
        if let window = pick.window, !withCamera {
            let size = window.frame.trimmedToEven
            return .window(id: window.windowID, pixelWidth: size.width, pixelHeight: size.height)
        }
        let pixels = pick.area.trimmedToEven
        let rect = pick.display.points(pixels)
        if let window = pick.window {
            return .windowInPlace(
                id: window.windowID, display: pick.display.id, rect: rect, pixelWidth: pixels.width,
                pixelHeight: pixels.height)
        }
        return .area(display: pick.display.id, rect: rect, pixelWidth: pixels.width, pixelHeight: pixels.height)
    }

    private func options(for pick: RecordingPick) async -> ScreenRecordingOptions {
        let settings = core.settings
        var options = ScreenRecordingOptions(
            capturesSystemAudio: settings.screenRecordingSystemAudio, showsClicks: settings.screenRecordingShowsClicks)
        guard pick.choices.microphone else { return options }
        guard await Permissions.ensureCaptureAccess(for: .audio) else {
            core.showMessage("Microphone access is off, so the recording has no voice", tone: .danger)
            return options
        }
        let chosen = settings.screenRecordingMicrophoneID.flatMap { id in microphones.first { $0.uniqueID == id } }
        options.microphone = chosen.map { .device(id: $0.uniqueID) } ?? .systemDefault
        return options
    }

    private func camera(for pick: RecordingPick) async -> RecordingCamera? {
        guard pick.choices.camera else { return nil }
        guard await Permissions.ensureCaptureAccess(for: .video) else {
            core.showMessage("Camera access is off, so the recording has no camera", tone: .danger)
            return nil
        }
        guard let camera = await RecordingCamera.start(deviceID: core.settings.screenRecordingCameraID) else {
            core.showMessage("Couldn't start the camera", tone: .danger)
            return nil
        }
        return camera
    }

    private func finish(_ outcome: ScreenRecordingController.Outcome) {
        recording = nil
        switch outcome {
        case .saved(let url):
            core.showMessage("Saved \(url.lastPathComponent)")
        case .discarded:
            return
        case .failed(let error):
            Self.logger.error("Screen recording failed: \(String(describing: error), privacy: .public)")
            core.showMessage("Couldn't record the screen", tone: .danger)
        }
    }
}
