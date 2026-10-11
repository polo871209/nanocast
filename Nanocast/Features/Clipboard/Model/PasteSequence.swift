import Foundation

struct PasteSequence: Sendable {
    static let idleTimeout: TimeInterval = 60
    static let settleInterval: TimeInterval = 0.25

    private let entryIDs: [ClipboardItem.ID]
    private var nextIndex = 0
    private var changeCount: Int
    private var lastPaste: Date

    init(history: [ClipboardItem], changeCount: Int, now: Date) {
        entryIDs = history.map(\.id)
        self.changeCount = changeCount
        lastPaste = now
    }

    func continues(changeCount: Int, at now: Date) -> Bool {
        changeCount == self.changeCount && now.timeIntervalSince(lastPaste) < Self.idleTimeout
    }

    func isSettling(at now: Date) -> Bool {
        now.timeIntervalSince(lastPaste) < Self.settleInterval
    }

    mutating func next(in history: [ClipboardItem]) -> ClipboardItem? {
        while nextIndex < entryIDs.endIndex {
            let id = entryIDs[nextIndex]
            nextIndex += 1
            if let item = history.first(where: { $0.id == id }) { return item }
        }
        return nil
    }

    mutating func recordPaste(changeCount: Int, at now: Date) {
        self.changeCount = changeCount
        lastPaste = now
    }
}
