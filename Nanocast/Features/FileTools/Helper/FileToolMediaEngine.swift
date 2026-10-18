import AVFoundation

nonisolated enum FileToolMediaEngine {
    private static let aacSampleRateLimit = 48_000.0
    private static let aacBitRate = 256_000
    private static let readFrames: AVAudioFrameCount = 65_536

    static func run(_ request: FileToolRequest) async throws {
        guard let source = request.sources.first else { throw FileToolEngine.Failure.unsupported }
        switch request.kind {
        case .changeSpeed, .changeSpeedAndPitch:
            guard case .speed(let speed)? = request.option else { throw FileToolEngine.Failure.unsupported }
            try await changeSpeed(
                source, to: request.destination, by: speed.factor, keepsPitch: request.kind == .changeSpeed)
        case .convertAudio:
            guard let format = request.audioFormat else { throw FileToolEngine.Failure.unsupported }
            var codec = FileToolAudioCodec.aac
            if case .codec(let chosen)? = request.option { codec = chosen }
            try convert(source, to: request.destination, as: format, codec: codec)
        case .convertVideo:
            guard let format = request.videoFormat else { throw FileToolEngine.Failure.unsupported }
            try await convert(source, to: request.destination, as: format)
        case .trimAudio:
            try await trim(source, to: request.destination, request.parameters)
        default:
            throw FileToolEngine.Failure.unsupported
        }
    }

    private static func changeSpeed(_ source: URL, to destination: URL, by factor: Double, keepsPitch: Bool) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        let scaled = CMTimeMultiplyByFloat64(duration, multiplier: 1 / factor)
        let composition = AVMutableComposition()
        for track in try await asset.loadTracks(withMediaType: .video) {
            let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            try copy?.insertTimeRange(range, of: track, at: .zero)
            copy?.preferredTransform = try await track.load(.preferredTransform)
        }
        let repitched = keepsPitch ? nil : try resampled(source, by: factor)
        defer { if let repitched { try? FileManager.default.removeItem(at: repitched) } }
        let audio = repitched.map(AVURLAsset.init(url:)) ?? asset
        for track in try await audio.loadTracks(withMediaType: .audio) {
            let length = repitched == nil ? duration : try await audio.load(.duration)
            try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
                .insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: .zero)
        }
        for track in composition.tracks where repitched == nil || track.mediaType == .video {
            track.scaleTimeRange(range, toDuration: scaled)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw FileToolEngine.Failure.unsupported }
        session.audioTimePitchAlgorithm = .spectral
        try await export(session, to: destination, as: fileType(for: source))
    }

    // `.varispeed` hangs AVAssetExportSession on short clips (macOS 27), so a higher sample rate repitches.
    private static func resampled(_ source: URL, by factor: Double) throws -> URL? {
        guard let input = try? AVAudioFile(forReading: source) else { return nil }
        let format = input.processingFormat
        guard
            let faster = AVAudioFormat(
                commonFormat: format.commonFormat, sampleRate: format.sampleRate * factor,
                channels: format.channelCount, interleaved: format.isInterleaved),
            let readBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: readFrames),
            let writeBuffer = AVAudioPCMBuffer(pcmFormat: faster, frameCapacity: readFrames)
        else { throw FileToolEngine.Failure.unreadable }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        var settings = faster.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        let output = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: faster.commonFormat,
            interleaved: faster.isInterleaved)
        while input.framePosition < input.length {
            try input.read(into: readBuffer)
            guard readBuffer.frameLength > 0, let from = readBuffer.floatChannelData,
                let to = writeBuffer.floatChannelData
            else { break }
            for channel in 0..<Int(format.channelCount) {
                to[channel].update(from: from[channel], count: Int(readBuffer.frameLength))
            }
            writeBuffer.frameLength = readBuffer.frameLength
            try output.write(from: writeBuffer)
        }
        return url
    }

    private static func trim(_ source: URL, to destination: URL, _ parameters: FileToolParameters) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let start = min(parameters.start ?? 0, duration)
        let end = min(parameters.end ?? duration, duration)
        guard end > start else { throw FileToolEngine.Failure.unsupported }
        let passthrough = FileToolAudioFormat.trimPassthroughExtensions.contains(source.pathExtension.lowercased())
        guard
            let session = AVAssetExportSession(
                asset: asset, presetName: passthrough ? AVAssetExportPresetPassthrough : AVAssetExportPresetAppleM4A)
        else { throw FileToolEngine.Failure.unsupported }
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        try await export(session, to: destination, as: passthrough ? fileType(for: source) : .m4a)
    }

    private static func convert(_ source: URL, to destination: URL, as format: FileToolVideoFormat) async throws {
        let asset = AVURLAsset(url: source)
        let type = fileType(for: format)
        let rewraps = await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetPassthrough, with: asset, outputFileType: type)
        guard
            let session = AVAssetExportSession(
                asset: asset, presetName: rewraps ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality)
        else { throw FileToolEngine.Failure.unsupported }
        try await export(session, to: destination, as: type)
    }

    private static func fileType(for format: FileToolVideoFormat) -> AVFileType {
        switch format {
        case .mov: .mov
        case .mp4: .mp4
        case .m4v: .m4v
        }
    }

    private static func export(_ session: AVAssetExportSession, to destination: URL, as type: AVFileType) async throws {
        let states = session.states(updateInterval: 0.25)
        let progress = Task {
            for await state in states {
                guard !Task.isCancelled else { return }
                if case .exporting(let progress) = state { FileToolEngine.report(progress.fractionCompleted) }
            }
        }
        defer { progress.cancel() }
        try await session.export(to: destination, as: type)
    }

    private static func fileType(for source: URL) -> AVFileType {
        switch source.pathExtension.lowercased() {
        case "mp4": .mp4
        case "m4v": .m4v
        case "m4a": .m4a
        case "wav": .wav
        case "aif", "aiff": .aiff
        default: .mov
        }
    }

    private static func convert(
        _ source: URL, to destination: URL, as format: FileToolAudioFormat, codec: FileToolAudioCodec
    ) throws {
        let input = try AVAudioFile(forReading: source)
        let processing = input.processingFormat
        let output = try AVAudioFile(
            forWriting: destination, settings: settings(for: format, codec: codec, source: input.fileFormat),
            commonFormat: processing.commonFormat, interleaved: processing.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: readFrames) else {
            throw FileToolEngine.Failure.unreadable
        }
        let length = max(input.length, 1)
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
            FileToolEngine.report(Double(input.framePosition) / Double(length))
        }
    }

    private static func settings(
        for format: FileToolAudioFormat, codec: FileToolAudioCodec, source: AVAudioFormat
    ) -> [String: Any] {
        let rate = source.sampleRate
        let channels = Int(source.channelCount)
        let sourceDepth = Int(source.streamDescription.pointee.mBitsPerChannel)
        let depth = [16, 24, 32].contains(sourceDepth) ? sourceDepth : 16
        switch format {
        case .m4a where codec == .aac:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: min(rate, aacSampleRateLimit),
                AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: aacBitRate
            ]
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
                AVEncoderBitDepthHintKey: min(depth, 24)
            ]
        case .flac:
            return [
                AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
                AVEncoderBitDepthHintKey: min(depth, 24)
            ]
        case .wav, .aiff:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: depth, AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: format == .aiff, AVLinearPCMIsNonInterleaved: false
            ]
        }
    }
}
