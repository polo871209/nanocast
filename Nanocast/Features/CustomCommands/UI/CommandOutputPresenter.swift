import Foundation
import SwiftUI

struct CommandOutcome: Sendable {
    let summary: String
    let hint: String?
    let succeeded: Bool
    let finishedAt: Date
}

struct CommandRun: Identifiable, Sendable {
    let id = UUID()
    let commandID: UUID
    let name: String
    let commandText: String
    let symbol: String
    let startedAt: Date
    var log = ""
    var delta = ""
    var revision = 0
    var generation = 0
    var outcome: CommandOutcome?

    var isRunning: Bool { outcome == nil }
}

@MainActor
@Observable
final class CommandOutputPresenter {
    private static let logLimit = 256 * 1024

    private(set) var run: CommandRun?

    @ObservationIgnored private let activation: ActivationPolicy
    @ObservationIgnored private let rerun: (UUID) -> Void
    @ObservationIgnored private let stop: (UUID) -> Void
    @ObservationIgnored private let openSettings: () -> Void
    @ObservationIgnored private lazy var window = AppWindowController(
        title: "Command Output", contentSize: CommandOutputView.initialSize,
        resizable: true, autosaveName: "CommandOutputWindow", activation: activation,
        closesOnEscape: true)

    init(
        activation: ActivationPolicy, rerun: @escaping (UUID) -> Void,
        stop: @escaping (UUID) -> Void, openSettings: @escaping () -> Void
    ) {
        self.activation = activation
        self.rerun = rerun
        self.stop = stop
        self.openSettings = openSettings
    }

    @discardableResult
    func begin(commandID: UUID, name: String, commandText: String, symbol: String) -> UUID {
        let run = CommandRun(
            commandID: commandID, name: name, commandText: commandText, symbol: symbol,
            startedAt: Date())
        self.run = run
        window.show { CommandOutputView(presenter: self) }
        return run.id
    }

    func append(_ text: String, to id: UUID) {
        guard var run, run.id == id else { return }
        run.log += text
        run.delta = text
        run.revision += 1
        if run.log.utf8.count > Self.logLimit {
            run.log = String(run.log.suffix(Self.logLimit / 2))
            run.generation += 1
        }
        self.run = run
    }

    func finish(_ outcome: CommandOutcome, for id: UUID) {
        guard var run, run.id == id else { return }
        run.outcome = outcome
        self.run = run
    }

    func runAgain() {
        guard let run else { return }
        rerun(run.commandID)
    }

    func stopRunning() {
        guard let run, run.isRunning else { return }
        stop(run.id)
    }

    func showCommandSettings() {
        openSettings()
    }

    func focusExisting() -> Bool {
        window.focus()
    }
}
