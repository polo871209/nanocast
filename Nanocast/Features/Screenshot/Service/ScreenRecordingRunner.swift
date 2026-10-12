import AVFoundation
import ScreenCaptureKit

@MainActor
final class ScreenRecordingRunner: NSObject {
    enum Source: Sendable {
        case area(display: CGDirectDisplayID, rect: CGRect, pixelWidth: Int, pixelHeight: Int)
        case window(id: UInt32, pixelWidth: Int, pixelHeight: Int)
    }

    enum RecordingError: Error {
        case sourceGone
    }

    private static let frameRate: Int32 = 60

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var hasStartedRecording = false
    private var isStopRequested = false
    private var isEnded = false
    private let started: () -> Void
    private let ended: (Result<Void, any Error>) -> Void

    init(started: @escaping () -> Void, ended: @escaping (Result<Void, any Error>) -> Void) {
        self.started = started
        self.ended = ended
    }

    func start(_ source: Source, writingTo url: URL, as format: ScreenRecordingFormat) async {
        do {
            let filter = try await Self.filter(for: source)
            guard !isStopRequested else { return end(.failure(CancellationError())) }
            let stream = SCStream(filter: filter, configuration: Self.configuration(for: source), delegate: self)
            let output = SCRecordingOutput(configuration: Self.recording(to: url, as: format), delegate: self)
            try stream.addRecordingOutput(output)
            self.stream = stream
            self.output = output
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                stream.startCapture { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            if isStopRequested { stop() }
        } catch {
            end(.failure(error))
        }
    }

    func stop() {
        isStopRequested = true
        stream?.stopCapture(completionHandler: nil)
    }

    private func end(_ result: Result<Void, any Error>) {
        guard !isEnded else { return }
        isEnded = true
        stream = nil
        output = nil
        ended(result)
    }

    private func recordingStarted() {
        guard !isEnded else { return }
        hasStartedRecording = true
        started()
    }

    private func streamStopped(_ error: any Error) {
        if !hasStartedRecording { end(.failure(error)) }
    }

    private static func configuration(for source: Source) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        switch source {
        case .area(_, let rect, let width, let height):
            configuration.sourceRect = rect
            configuration.width = width
            configuration.height = height
        case .window(_, let width, let height):
            configuration.width = width
            configuration.height = height
        }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: frameRate)
        configuration.showsCursor = true
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
    private static func filter(for source: Source) async throws -> sending SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        switch source {
        case .area(let id, _, _, _):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw RecordingError.sourceGone
            }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            return SCContentFilter(
                display: display, excludingApplications: content.applications.filter { $0.processID == ownPID },
                exceptingWindows: [])
        case .window(let id, _, _):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw RecordingError.sourceGone
            }
            return SCContentFilter(desktopIndependentWindow: window)
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
        Task { @MainActor in self.end(.failure(error)) }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.end(.success(())) }
    }
}
