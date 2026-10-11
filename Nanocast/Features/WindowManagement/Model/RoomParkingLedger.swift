// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

@MainActor
final class RoomParkingLedger {
    struct Entry: Codable, Equatable, Sendable {
        var windowID: UInt32
        var bundleID: String
        var title: String
        var frame: CGRect
    }

    private let fileURL: URL
    private(set) var entries: [UInt32: Entry]

    init(fileURL: URL) {
        self.fileURL = fileURL
        entries = Self.load(from: fileURL)
    }

    var isEmpty: Bool { entries.isEmpty }

    func entry(for windowID: UInt32) -> Entry? {
        entries[windowID]
    }

    func record(_ entry: Entry) -> Bool {
        if entries[entry.windowID] == nil { entries[entry.windowID] = entry }
        return save()
    }

    func forget(_ windowIDs: some Sequence<UInt32>) {
        let before = entries.count
        for id in windowIDs { entries[id] = nil }
        if entries.count != before { save() }
    }

    func keepOnly(bundleIDs: Set<String>) {
        let kept = entries.filter { bundleIDs.contains($0.value.bundleID) }
        guard kept.count != entries.count else { return }
        entries = kept
        save()
    }

    @discardableResult
    private func save() -> Bool {
        do {
            let list = entries.values.sorted { $0.windowID < $1.windowID }
            try JSONEncoder().encode(list).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func load(from url: URL) -> [UInt32: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let list = try? JSONDecoder().decode([Entry].self, from: data) else {
            let name = url.deletingPathExtension().lastPathComponent
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("\(name).unreadable-\(UUID().uuidString).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return [:]
        }
        return Dictionary(list.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
