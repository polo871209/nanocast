import Darwin
import Foundation
import Synchronization

enum ShellCommandTermination: Sendable, Equatable {
    case exited(status: Int32)
    case launchFailed(String)
    case stopped

    var succeeded: Bool { self == .exited(status: 0) }
}

enum ShellCommandEvent: Sendable {
    case output(String)
    case finished(ShellCommandResult)
}

struct ShellCommandSession: Sendable {
    let events: AsyncStream<ShellCommandEvent>
    let stop: @Sendable () -> Void
}

struct ShellCommandResult: Sendable, Equatable {
    let termination: ShellCommandTermination
    let standardOutput: String?
    let standardError: String?

    var succeeded: Bool { termination.succeeded }

    var lastOutputLine: String? {
        standardOutput?
            .split(whereSeparator: \.isNewline).last
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    init(
        termination: ShellCommandTermination, standardOutput: String? = nil,
        standardError: String? = nil
    ) {
        self.termination = termination
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

enum ShellCommandRunner {
    private static let standardErrorLimit = 8 * 1024
    private static let standardOutputLimit = 4 * 1024
    private static let shell = "/bin/zsh"
    private static let readSize = 16 * 1024
    private static let flushInterval: Duration = .milliseconds(40)
    private static let unlinedLimit = 4 * 1024
    private static let stopGrace: DispatchTimeInterval = .seconds(2)
    private static let queue = DispatchQueue(
        label: "com.nanocast.shell-command", qos: .userInitiated, attributes: .concurrent)

    nonisolated static func run(
        _ command: String, arguments: [String] = [], loadingShellEnvironment: Bool = false,
        workingDirectory: String? = nil
    ) async -> ShellCommandResult {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(
                    returning: execute(
                        command, arguments: arguments,
                        loadingShellEnvironment: loadingShellEnvironment,
                        workingDirectory: workingDirectory))
            }
        }
    }

    nonisolated private static func execute(
        _ command: String, arguments: [String], loadingShellEnvironment: Bool,
        workingDirectory: String?
    ) -> ShellCommandResult {
        let launch: Launch
        do {
            launch = try prepare(
                command, arguments: arguments, loadingShellEnvironment: loadingShellEnvironment,
                workingDirectory: workingDirectory)
        } catch {
            return ShellCommandResult(termination: .launchFailed(error.reason))
        }
        defer { launch.removeScript() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = launch.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: launch.directory)
        process.environment = ProcessInfo.processInfo.environment.merging(["NANOCAST": "1"]) { _, new in
            new
        }
        process.standardInput = FileHandle.nullDevice

        let output = StreamCapture.make()
        let errors = StreamCapture.make()
        process.standardOutput = output?.handle ?? FileHandle.nullDevice
        process.standardError = errors?.handle ?? FileHandle.nullDevice
        defer {
            output?.remove()
            errors?.remove()
        }

        do {
            try process.runObservingExit().wait()
        } catch {
            return ShellCommandResult(termination: .launchFailed(error.localizedDescription))
        }

        return ShellCommandResult(
            termination: .exited(status: process.terminationStatus),
            standardOutput: output?.readSuffix(limit: standardOutputLimit),
            standardError: errors?.readSuffix(limit: standardErrorLimit))
    }

    nonisolated static func stream(
        _ command: String, arguments: [String] = [], loadingShellEnvironment: Bool = false,
        workingDirectory: String? = nil
    ) -> ShellCommandSession {
        let launch: Launch
        do {
            launch = try prepare(
                command, arguments: arguments, loadingShellEnvironment: loadingShellEnvironment,
                workingDirectory: workingDirectory)
        } catch {
            return failedSession(error.reason)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["NANOCAST"] = "1"
        environment["TERM"] = "xterm-256color"

        guard
            let terminal = PseudoTerminal.spawn(
                executable: shell, arguments: launch.arguments, environment: environment,
                workingDirectory: launch.directory)
        else {
            launch.removeScript()
            return failedSession(String(localized: "The shell could not be started."))
        }

        let stopped = StopFlag()
        let events = AsyncStream<ShellCommandEvent> { continuation in
            queue.async {
                drain(terminal, stopped: stopped, into: continuation)
                launch.removeScript()
            }
        }
        return ShellCommandSession(
            events: events,
            stop: { [weak stopFlag = stopped] in
                stopFlag?.mark()
                terminal.signalSession(SIGTERM)
                queue.asyncAfter(deadline: .now() + stopGrace) {
                    terminal.signalSession(SIGKILL)
                }
            })
    }

    nonisolated private static func failedSession(_ reason: String) -> ShellCommandSession {
        ShellCommandSession(
            events: AsyncStream { continuation in
                continuation.yield(.finished(ShellCommandResult(termination: .launchFailed(reason))))
                continuation.finish()
            },
            stop: {})
    }

    nonisolated private static func drain(
        _ terminal: PseudoTerminal, stopped: StopFlag,
        into continuation: AsyncStream<ShellCommandEvent>.Continuation
    ) {
        var decoder = TerminalTextDecoder()
        var buffer = [UInt8](repeating: 0, count: readSize)
        var lastYield = ContinuousClock().now

        while true {
            // Zero is EOF; -1 with EIO is what a pty master returns once its child is gone.
            let count = read(terminal.parentEnd, &buffer, readSize)
            guard count > 0 else { break }
            decoder.append(buffer, count: count)
            let due = ContinuousClock().now - lastYield >= flushInterval
            if let text = decoder.take(force: due) {
                continuation.yield(.output(text))
                lastYield = ContinuousClock().now
            }
        }
        if let text = decoder.take(force: true) { continuation.yield(.output(text)) }

        let status = terminal.wait()
        terminal.close()
        continuation.yield(
            .finished(
                ShellCommandResult(
                    termination: stopped.isSet ? .stopped : .exited(status: status))))
        continuation.finish()
    }

    private final class StopFlag: Sendable {
        private let value = Mutex(false)

        var isSet: Bool { value.withLock { $0 } }

        func mark() { value.withLock { $0 = true } }
    }

    private struct TerminalTextDecoder {
        private var pending: [UInt8] = []

        mutating func append(_ bytes: [UInt8], count: Int) {
            pending.append(contentsOf: bytes[0..<count])
        }

        mutating func take(force: Bool) -> String? {
            guard !pending.isEmpty else { return nil }
            var end = pending.lastIndex(of: 0x0A).map { $0 + 1 }
            if end == nil {
                guard force || pending.count >= unlinedLimit else { return nil }
                end = scalarBoundary(before: pending.count)
            }
            guard let end, end > 0 else { return nil }
            let bytes = Array(pending[0..<end])
            pending.removeFirst(end)
            return String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1)
        }

        private func scalarBoundary(before index: Int) -> Int {
            var boundary = index
            var stepped = 0
            while boundary > 0, stepped < 4, pending[boundary - 1] & 0xC0 == 0x80 {
                boundary -= 1
                stepped += 1
            }
            guard boundary > 0 else { return index }
            let lead = pending[boundary - 1]
            let width = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
            return index - boundary + 1 >= width ? index : boundary - 1
        }
    }

    nonisolated private static func resolvedWorkingDirectory(_ path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return expanded
    }

    private struct Launch: Sendable {
        let arguments: [String]
        let directory: String
        let script: URL?

        func removeScript() {
            guard let script else { return }
            try? FileManager.default.removeItem(at: script)
        }
    }

    private struct LaunchFailure: Error {
        let reason: String
    }

    nonisolated private static func prepare(
        _ command: String, arguments: [String], loadingShellEnvironment: Bool,
        workingDirectory: String?
    ) throws(LaunchFailure) -> Launch {
        guard let directory = resolvedWorkingDirectory(workingDirectory) else {
            throw LaunchFailure(
                reason: String(localized: "The folder “\(workingDirectory ?? "")” no longer exists."))
        }
        // zsh reads `.zshrc` only for interactive shells, so `-l` alone sees no aliases.
        let flag = loadingShellEnvironment ? "-ilc" : "-lc"
        guard command.hasPrefix("#!") else {
            return Launch(
                arguments: [flag, command, "nanocast"] + arguments, directory: directory,
                script: nil)
        }
        // The kernel reads the `#!` line, so the text reaches its interpreter unparsed by zsh.
        let script = FileManager.default.temporaryDirectory
            .appending(path: "nanocast-command-script-\(UUID().uuidString)")
        guard
            FileManager.default.createFile(
                atPath: script.path, contents: Data(command.utf8),
                attributes: [.posixPermissions: 0o700])
        else { throw LaunchFailure(reason: String(localized: "The script could not be written.")) }
        return Launch(
            arguments: [flag, #"exec "$0" "$@""#, script.path] + arguments, directory: directory,
            script: script)
    }

    private final class StreamCapture: Sendable {
        let url: URL
        let handle: FileHandle

        init(url: URL, handle: FileHandle) {
            self.url = url
            self.handle = handle
        }

        func readSuffix(limit: Int) -> String? {
            try? handle.synchronize()
            guard let end = try? handle.seekToEnd() else { return nil }
            let start = end > UInt64(limit) ? end - UInt64(limit) : 0
            try? handle.seek(toOffset: start)
            guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
            let body = start > 0 ? data.drop { $0 & 0xC0 == 0x80 } : data[...]
            return String(decoding: body, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        func remove() {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
        }

        static func make() -> StreamCapture? {
            let template = FileManager.default.temporaryDirectory
                .appendingPathComponent("nanocast-command-stream.XXXXXX").path
            var bytes = Array(template.utf8CString)
            let descriptor = bytes.withUnsafeMutableBufferPointer { buffer in
                mkstemp(buffer.baseAddress!)
            }
            guard descriptor >= 0 else { return nil }
            let path = String(
                decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return StreamCapture(
                url: URL(fileURLWithPath: path),
                handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
        }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
