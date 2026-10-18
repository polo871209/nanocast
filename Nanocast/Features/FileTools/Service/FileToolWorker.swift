import Foundation

nonisolated enum FileToolWorker {
    enum Failure: Error { case helper }

    typealias Progress = @Sendable (Double) -> Void

    static let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/FileToolHelper")
    private static let readSize = 4096
    private static let progressPrefix = "progress "
    private static let queue = DispatchQueue(
        label: "com.nanocast.file-tools", qos: .userInitiated, attributes: .concurrent)

    /// Writes into a staging folder on the destination's volume, then moves the result into place.
    @concurrent
    static func run(
        _ request: FileToolRequest, executable: URL = executable, timeout: Duration = .seconds(120),
        progress: @escaping Progress = { _ in }
    ) async throws {
        let manager = FileManager.default
        let staging = try manager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: request.destination,
            create: true)
        defer { try? manager.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(request.destination.lastPathComponent)
        try await launch(request.staged(at: staged), executable: executable, timeout: timeout, progress: progress)
        try Task.checkCancellation()
        try manager.moveItem(at: staged, to: request.destination)
    }

    /// Runs a job whose result is text, such as a QR code's payload, and returns that text.
    @concurrent
    static func read(
        _ request: FileToolRequest, executable: URL = executable, timeout: Duration = .seconds(120)
    ) async throws -> String {
        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        let staged = staging.appendingPathComponent("result.txt")
        try await launch(request.staged(at: staged), executable: executable, timeout: timeout) { _ in }
        try Task.checkCancellation()
        return try String(contentsOf: staged, encoding: .utf8)
    }

    private static func launch(
        _ request: FileToolRequest, executable: URL, timeout: Duration, progress: @escaping Progress
    ) async throws {
        try Task.checkCancellation()
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = [String(decoding: try JSONEncoder().encode(request), as: UTF8.self)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .userInitiated
        guard let exit = try? process.runObservingExit() else { throw Failure.helper }
        if Task.isCancelled { terminate(process) }
        let deadline = Task.detached(priority: .background) {
            do { try await Task.sleep(for: timeout) } catch { return }
            terminate(process)
        }
        let status = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    forwardProgress(from: output.fileHandleForReading, to: progress)
                    exit.wait()
                    continuation.resume(returning: process.terminationStatus)
                }
            }
        } onCancel: {
            terminate(process)
        }
        deadline.cancel()
        try Task.checkCancellation()
        guard status == 0 else { throw Failure.helper }
    }

    private static func forwardProgress(from reader: FileHandle, to progress: Progress) {
        defer { try? reader.close() }
        var pending = Data()
        while let chunk = try? reader.read(upToCount: readSize), !chunk.isEmpty {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newline)
                if line.hasPrefix(progressPrefix), let fraction = Double(line.dropFirst(progressPrefix.count)) {
                    progress(fraction)
                }
            }
        }
    }

    /// `terminate()` traps on a process that never launched, so the state has to be asked first.
    private static func terminate(_ process: Process) {
        if process.isRunning { process.terminate() }
    }
}
