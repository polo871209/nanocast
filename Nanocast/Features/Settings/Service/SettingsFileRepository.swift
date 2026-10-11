import Foundation
import Observation

@MainActor
final class SettingsFileRepository {
    var onIssues: (([SettingsFileIssue]) -> Void)?

    private let fileURL: URL
    private let bindings: [SettingsFileBinding]
    private let commit: () -> [SettingsFileIssue]
    private let monitor: SettingsFileMonitor
    private var lastSeen: Data?
    private var baseline: Data?
    private var saveTask: Task<Void, Never>?

    private static let saveDelay = Duration.milliseconds(300)

    init(
        fileURL: URL, bindings: [SettingsFileBinding],
        commit: @escaping () -> [SettingsFileIssue] = { [] }
    ) {
        self.fileURL = fileURL
        self.bindings = bindings
        self.commit = commit
        monitor = SettingsFileMonitor(fileURL: fileURL)
    }

    isolated deinit {
        saveTask?.cancel()
    }

    func start(importing: Bool) {
        if importing, FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try? Data(contentsOf: fileURL)
            lastSeen = data
            let issues = data.map { apply($0) } ?? [.unreadable]
            baseline = renderObserved()
            report(issues)
        } else {
            save()
        }
        monitor.onChange = { [weak self] in self?.reload() }
        monitor.start()
    }

    func flush() {
        guard let saveTask else { return }
        saveTask.cancel()
        save()
    }

    private func reload() {
        guard let data = try? Data(contentsOf: fileURL), data != lastSeen else { return }
        lastSeen = data
        let issues = apply(data)
        baseline = render()
        report(issues)
    }

    private func apply(_ data: Data) -> [SettingsFileIssue] {
        do {
            let parsed = try SettingsFileFormat.parse(data)
            return parsed.issues + apply(parsed.values)
        } catch {
            return [error]
        }
    }

    private func apply(_ values: [SettingsFileKey: SettingsFileJSON]) -> [SettingsFileIssue] {
        bindings.flatMap { binding in
            values[binding.key].map(binding.write) ?? []
        } + commit()
    }

    private func render() -> Data {
        SettingsFileFormat.render(
            Dictionary(uniqueKeysWithValues: bindings.map { ($0.key, $0.read()) }))
    }

    private func renderObserved() -> Data {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.scheduleSave() }
        }
    }

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.saveDelay)
            } catch {
                return
            }
            self?.save()
        }
    }

    private func save() {
        saveTask = nil
        let data = renderObserved()
        guard data != baseline else { return }
        if !write(data) { report([.unwritable]) }
    }

    private func write(_ data: Data) -> Bool {
        let target = fileURL.resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            return false
        }
        lastSeen = data
        baseline = data
        return true
    }

    private func report(_ issues: [SettingsFileIssue]) {
        guard !issues.isEmpty else { return }
        onIssues?(issues)
    }
}
