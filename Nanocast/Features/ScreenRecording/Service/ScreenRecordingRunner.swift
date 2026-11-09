import AVFoundation
import ScreenCaptureKit

@MainActor
final class ScreenRecordingRunner: NSObject {
    enum Source: Sendable {
        case area(display: CGDirectDisplayID, rect: CGRect, pixelWidth: Int, pixelHeight: Int)
        case window(id: UInt32, pixelWidth: Int, pixelHeight: Int)
        case windowInPlace(
            id: UInt32, display: CGDirectDisplayID, rect: CGRect, pixelWidth: Int, pixelHeight: Int)
    }

    enum RecordingError: Error {
        case sourceGone
        case stopRefused
    }

    private static let frameRate: Int32 = 60

    private let started: () -> Void
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var isRecording = false
    private var isStopRequested = false
    private var finished: CheckedContinuation<Void, any Error>?

    init(started: @escaping () -> Void) {
        self.started = started
    }

    func record(
        _ source: Source, with options: ScreenRecordingOptions, showing ownWindows: [CGWindowID], to url: URL,
        as format: ScreenRecordingFormat
    ) async throws {
        let filter = try await Self.filter(for: source, showing: ownWindows)
        guard !isStopRequested else { throw CancellationError() }
        let stream = SCStream(
            filter: filter, configuration: Self.configuration(for: source, with: options), delegate: self)
        let output = SCRecordingOutput(configuration: Self.recording(to: url, as: format), delegate: self)
        try stream.addRecordingOutput(output)
        self.stream = stream
        self.output = output
        defer {
            self.stream = nil
            self.output = nil
        }
        try await withCheckedThrowingContinuation { continuation in
            finished = continuation
            stream.startCapture { error in
                guard let error else { return }
                Task { @MainActor in self.end(.failure(error)) }
            }
        }
    }

    func stop() {
        guard !isStopRequested else { return }
        isStopRequested = true
        if isRecording { stopCapture() }
    }

    private func stopCapture() {
        guard let stream else { return }
        Task {
            for _ in 0..<50 {
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                        stream.stopCapture { error in
                            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                        }
                    }
                    return
                } catch SCStreamError.attemptToStopStreamState {
                    // ScreenCaptureKit rejects a stop in a stream's first ~30 ms (SCStreamError -3808).
                    try? await Task.sleep(for: .milliseconds(20))
                } catch {
                    return end(.failure(error))
                }
            }
            end(.failure(RecordingError.stopRefused))
        }
    }

    private func end(_ result: Result<Void, any Error>) {
        finished?.resume(with: result)
        finished = nil
    }

    private func recordingStarted() {
        isRecording = true
        if isStopRequested { stopCapture() } else { started() }
    }

    private func recordingFailed(_ error: any Error, wroteNothing: Bool) {
        end(.failure(isStopRequested && wroteNothing ? CancellationError() : error))
    }

    private func streamStopped(_ error: any Error) {
        if !isRecording { end(.failure(error)) }
    }

    private static func configuration(
        for source: Source, with options: ScreenRecordingOptions
    )
        -> SCStreamConfiguration
    {
        let configuration = SCStreamConfiguration()
        switch source {
        case .area(_, let rect, let width, let height), .windowInPlace(_, _, let rect, let width, let height):
            configuration.sourceRect = rect
            configuration.width = width
            configuration.height = height
        case .window(_, let width, let height):
            configuration.width = width
            configuration.height = height
        }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: frameRate)
        configuration.showsCursor = true
        configuration.showMouseClicks = options.showsClicks
        configuration.capturesAudio = options.capturesSystemAudio
        configuration.excludesCurrentProcessAudio = true
        if let microphone = options.microphone {
            configuration.captureMicrophone = true
            if case .device(let id) = microphone { configuration.microphoneCaptureDeviceID = id }
        }
        return configuration
    }

    private static func recording(to url: URL, as format: ScreenRecordingFormat) -> SCRecordingOutputConfiguration {
        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType =
            switch format {
            case .mov: .mov
            case .mp4: .mp4
            }
        recording.videoCodecType = .hevc
        return recording
    }

    @concurrent
    private static func filter(
        for source: Source, showing ownWindows: [CGWindowID]
    ) async throws
        -> sending SCContentFilter
    {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        func display(_ id: CGDirectDisplayID) throws -> SCDisplay {
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw RecordingError.sourceGone
            }
            return display
        }
        switch source {
        case .area(let id, _, _, _):
            let display = try display(id)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            return SCContentFilter(
                display: display, excludingApplications: content.applications.filter { $0.processID == ownPID },
                exceptingWindows: content.windows.filter { ownWindows.contains($0.windowID) })
        case .window(let id, _, _):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw RecordingError.sourceGone
            }
            return SCContentFilter(desktopIndependentWindow: window)
        case .windowInPlace(let id, let displayID, _, _, _):
            let display = try display(displayID)
            guard content.windows.contains(where: { $0.windowID == id }) else { throw RecordingError.sourceGone }
            return SCContentFilter(
                display: display, including: content.windows.filter { $0.windowID == id || ownWindows.contains($0.windowID) })
        }
    }
}

extension ScreenRecordingRunner: SCStreamDelegate, SCRecordingOutputDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in self.streamStopped(error) }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.recordingStarted() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let wroteNothing = recordingOutput.recordedFileSize == 0
        Task { @MainActor in self.recordingFailed(error, wroteNothing: wroteNothing) }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.end(.success(())) }
    }
}
