import CoreGraphics
import Foundation

struct WindowActionMemory<Key: Hashable> {
    struct Record: Equatable, Sendable {
        var restoreFrame: CGRect
        var appliedFrame: CGRect
        var command: WindowCommand.ID?
        var step: Int
        var screenID: Int
        var originScreenID: Int
        var at: Date
    }

    struct Decision: Equatable, Sendable {
        var step: Int
        var originScreenID: Int
        var restoreFrame: CGRect
        var canRestore: Bool
        var lastTileCommand: WindowCommand.ID?
    }

    static var tolerance: CGFloat { 2 }

    var capacity: Int
    var cycleTimeout: TimeInterval?

    private var records: [Key: Record] = [:]
    private var order: [Key] = []

    init(capacity: Int = 64, cycleTimeout: TimeInterval? = nil) {
        self.capacity = capacity
        self.cycleTimeout = cycleTimeout
    }

    var count: Int { records.count }

    func record(for key: Key) -> Record? { records[key] }

    func decide(
        key: Key, command: WindowCommand.ID?, currentFrame: CGRect, currentScreenID: Int,
        cycleLength: Int, now: Date
    ) -> Decision {
        guard let record = records[key] else {
            return Decision(
                step: 0, originScreenID: currentScreenID, restoreFrame: currentFrame,
                canRestore: false, lastTileCommand: nil)
        }

        guard approximatelyEqual(currentFrame, record.appliedFrame) else {
            return Decision(
                step: 0, originScreenID: currentScreenID, restoreFrame: currentFrame,
                canRestore: true, lastTileCommand: nil)
        }

        let lastTileCommand = record.command.flatMap {
            WindowPlacementEngine.isTileCommand($0) ? $0 : nil
        }
        let expired = cycleTimeout.map { now.timeIntervalSince(record.at) > $0 } ?? false
        let continues =
            cycleLength > 1 && command == record.command
            && currentScreenID == record.screenID && !expired
        return Decision(
            step: continues ? (record.step + 1) % cycleLength : 0,
            originScreenID: continues ? record.originScreenID : currentScreenID,
            restoreFrame: record.restoreFrame, canRestore: true, lastTileCommand: lastTileCommand)
    }

    mutating func commit(
        key: Key, command: WindowCommand.ID?, decision: Decision, appliedFrame: CGRect,
        screenID: Int, now: Date
    ) {
        records[key] = Record(
            restoreFrame: decision.restoreFrame, appliedFrame: appliedFrame, command: command,
            step: decision.step, screenID: screenID, originScreenID: decision.originScreenID,
            at: now)
        touch(key)
    }

    mutating func forgetCycle(key: Key) {
        guard var record = records[key] else { return }
        record.step = 0
        record.originScreenID = record.screenID
        records[key] = record
    }

    mutating func forget(where predicate: (Key) -> Bool) {
        let doomed = records.keys.filter(predicate)
        guard !doomed.isEmpty else { return }
        for key in doomed { records.removeValue(forKey: key) }
        order.removeAll { doomed.contains($0) }
    }

    mutating func forget(key: Key) {
        guard records.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            records.removeValue(forKey: oldest)
        }
    }

    private func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        let tolerance = Self.tolerance
        return abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
