import AVFoundation
import ScreenCaptureKit
import Synchronization

final class MicrophoneMeter: NSObject, SCStreamOutput, Sendable {
    private static let reportGap = Duration.milliseconds(66)

    private let report: @MainActor @Sendable (Float) -> Void
    private let lastReport = Mutex<ContinuousClock.Instant?>(nil)

    init(report: @escaping @MainActor @Sendable (Float) -> Void) {
        self.report = report
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .microphone, isTimeToReport(), let level = Self.level(of: sampleBuffer) else { return }
        let report = report
        Task { @MainActor in report(level) }
    }

    private func isTimeToReport() -> Bool {
        let now = ContinuousClock.now
        return lastReport.withLock { last in
            if let last, last.duration(to: now) < Self.reportGap { return false }
            last = now
            return true
        }
    }

    private static func level(of sampleBuffer: CMSampleBuffer) -> Float? {
        guard let format = sampleBuffer.formatDescription?.audioStreamBasicDescription,
            format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            format.mBitsPerChannel == 32
        else { return nil }
        let squares = try? sampleBuffer.withAudioBufferList { buffers, _ -> (sum: Float, count: Int) in
            var sum: Float = 0
            var count = 0
            for buffer in buffers {
                let samples = UnsafeBufferPointer(
                    start: buffer.mData?.assumingMemoryBound(to: Float.self),
                    count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                for sample in samples { sum += sample * sample }
                count += samples.count
            }
            return (sum, count)
        }
        guard let squares, squares.count > 0 else { return nil }
        let decibels = 10 * log10(max(squares.sum / Float(squares.count), 1e-10))
        return min(max((decibels + 50) / 50, 0), 1)
    }
}
