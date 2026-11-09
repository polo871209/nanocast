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

    var format: ScreenRecordingFormat {
        core.settings.screenRecordingFormat
    }

    func toggle() {
        if let recording { return recording.recordOrStop() }
        guard Permissions.isScreenRecordingGranted() else {
            Task { await askForScreenRecording() }
            return
        }
        guard let display = NSScreen.underCursor?.displayID else { return }
        if core.paletteCoordinator.isVisible { core.paletteCoordinator.hidePalette(restoreFocus: false) }
        let settings = core.settings
        let controller = ScreenRecordingController(
            target: .display(display), coordinator: self, metrics: settings.interfaceSize.metrics)
        recording = controller
        controller.start(microphone: settings.screenRecordingMicrophone, camera: settings.screenRecordingCamera)
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

    func remember(microphone: Bool) {
        core.settings.screenRecordingMicrophone = microphone
    }

    func remember(camera: Bool) {
        core.settings.screenRecordingCamera = camera
    }

    var cameraDiameter: CGFloat? {
        get { core.settings.screenRecordingCameraDiameter.map { CGFloat($0) } }
        set { core.settings.screenRecordingCameraDiameter = newValue.map { Double($0) } }
    }

    func pickArea(_ picked: @escaping (RecordingTarget?) -> Void) -> Bool {
        core.screenshotCoordinator.pickRecordingArea { pick in
            picked(
                pick.map { pick in
                    if let window = pick.window { return .window(window.windowID) }
                    return .area(display: pick.display.id, rect: pick.display.points(pick.area))
                })
        }
    }

    func options(microphone: Bool) -> ScreenRecordingOptions {
        let settings = core.settings
        var options = ScreenRecordingOptions(
            capturesSystemAudio: settings.screenRecordingSystemAudio, showsClicks: settings.screenRecordingShowsClicks)
        guard microphone else { return options }
        let chosen = settings.screenRecordingMicrophoneID.flatMap { id in microphones.first { $0.uniqueID == id } }
        options.microphone = chosen.map { .device(id: $0.uniqueID) } ?? .systemDefault
        return options
    }

    func allowsMicrophone() async -> Bool {
        guard await Permissions.ensureCaptureAccess(for: .audio) else {
            core.showMessage("Microphone access is off in System Settings", tone: .danger)
            return false
        }
        return true
    }

    func startCamera() async -> RecordingCamera? {
        guard await Permissions.ensureCaptureAccess(for: .video) else {
            core.showMessage("Camera access is off in System Settings", tone: .danger)
            return nil
        }
        guard let camera = await RecordingCamera.start(deviceID: core.settings.screenRecordingCameraID) else {
            core.showMessage("Couldn't start the camera", tone: .danger)
            return nil
        }
        return camera
    }

    func finish(_ outcome: ScreenRecordingController.Outcome) {
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

    private func askForScreenRecording() async {
        guard
            await core.confirm(
                title: "Allow Screen Recording?",
                message: "Nanocast captures the screen only while you record. "
                    + "Turn on Screen Recording for Nanocast, then try again.",
                symbol: "record.circle", confirmTitle: "Open System Settings", tone: .neutral,
                confirmRole: .standard)
        else { return }
        Permissions.requestScreenRecording()
        Permissions.openScreenRecordingSettings()
    }
}
