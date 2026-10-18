import Foundation
import Observation

@MainActor
@Observable
final class FileToolsSession {
    struct Job: Equatable {
        let id: Int
        let tool: FileTool
        var progress: Double?
    }

    struct Outcome: Equatable {
        enum Kind: Equatable {
            case saved
            case moved(folder: String)
            case copied(folder: String)
        }

        let kind: Kind
        let outputs: [URL]
        let inputBytes: Int?
        let outputBytes: Int?
    }

    private(set) var subject: FileToolsSubject?
    private(set) var tools: [FileTool] = []
    private(set) var job: Job?
    private(set) var outcome: Outcome?
    private(set) var options: [FileToolOptionSlot: FileToolOption] = [:]
    @ObservationIgnored private var lastJobID = 0

    func begin(_ subject: FileToolsSubject, tools: [FileTool], outcome: Outcome? = nil) {
        self.subject = subject
        self.tools = tools
        self.outcome = outcome
    }

    func restore(_ options: [FileToolOption]) {
        self.options = Dictionary(options.map { ($0.slot, $0) }, uniquingKeysWith: { _, last in last })
    }

    func option(for tool: FileTool) -> FileToolOption? {
        guard let slot = tool.slot else { return nil }
        return options[slot] ?? slot.defaultOption
    }

    func choose(_ option: FileToolOption, for tool: FileTool) {
        guard tool.options.contains(option) else { return }
        options[option.slot] = option
    }

    func startJob(_ tool: FileTool) -> Int {
        lastJobID += 1
        job = Job(id: lastJobID, tool: tool)
        return lastJobID
    }

    func report(_ progress: Double, for id: Int) {
        guard job?.id == id else { return }
        job?.progress = progress
    }

    func endJob(_ id: Int) -> Bool {
        guard job?.id == id else { return false }
        job = nil
        return true
    }

    func reset() {
        subject = nil
        tools = []
        job = nil
        outcome = nil
    }
}
