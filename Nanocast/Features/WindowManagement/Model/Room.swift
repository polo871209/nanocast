// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import Foundation

struct Room: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "window-room:"
    static let sfSymbol = "door.left.hand.open"

    let id: UUID
    var name: String
    var windows: [RoomWindow]
    var layout: RoomLayoutKind
    var layoutsByDisplay: [String: RoomLayoutKind]
    var lastEnteredAt: Date?

    init(
        id: UUID = UUID(), name: String, windows: [RoomWindow] = [],
        layout: RoomLayoutKind = .auto, layoutsByDisplay: [String: RoomLayoutKind] = [:],
        lastEnteredAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.windows = windows
        self.layout = layout
        self.layoutsByDisplay = layoutsByDisplay
        self.lastEnteredAt = lastEnteredAt
    }

    func layout(onDisplay uuid: String?) -> RoomLayoutKind {
        uuid.flatMap { layoutsByDisplay[$0.lowercased()] } ?? layout
    }

    func keepingRuntime(of learned: Room) -> Room {
        var room = self
        room.lastEnteredAt = learned.lastEnteredAt
        for (index, window) in zip(room.windows.indices, learned.windows)
        where window.bundleID == room.windows[index].bundleID {
            room.windows[index].windowID = window.windowID
        }
        return room
    }

    var summary: String { windows.count == 1 ? "1 window" : "\(windows.count) windows" }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        guard order == .orderedSame else { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func enteredMoreRecently(_ lhs: Self, _ rhs: Self) -> Bool {
        let left = lhs.lastEnteredAt ?? .distantPast
        let right = rhs.lastEnteredAt ?? .distantPast
        return left != right ? left > right : precedes(lhs, rhs)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, windows, layout, layoutsByDisplay, lastEnteredAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        windows = try container.decodeIfPresent([RoomWindow].self, forKey: .windows) ?? []
        layout = (try? container.decodeIfPresent(RoomLayoutKind.self, forKey: .layout)) ?? .auto
        let stored =
            (try? container.decodeIfPresent([String: String].self, forKey: .layoutsByDisplay)) ?? [:]
        layoutsByDisplay = stored.compactMapValues(RoomLayoutKind.init(rawValue:))
        lastEnteredAt = try container.decodeIfPresent(Date.self, forKey: .lastEnteredAt)
    }
}

enum RoomValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case noWindows
    case invalidCharacter

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the room."
        case .duplicateName: return "A room with this name already exists."
        case .noWindows: return "Choose at least one window for the room."
        case .invalidCharacter: return "Names cannot contain null characters."
        }
    }
}
