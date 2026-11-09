import AVFoundation

enum RecordingJoinService {
    @concurrent
    static func join(_ segments: [URL], into url: URL, as format: ScreenRecordingFormat) async throws {
        if segments.count == 1 {
            return try FileManager.default.moveItem(at: segments[0], to: url)
        }
        let movie = AVMutableComposition()
        for segment in segments {
            let asset = AVURLAsset(url: segment)
            let duration = try await asset.load(.duration)
            try await movie.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: asset, at: movie.duration)
        }
        guard let export = AVAssetExportSession(asset: movie, presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try await export.export(to: url, as: format.fileType)
    }
}
