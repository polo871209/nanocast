import Foundation

@MainActor
@Observable
final class RoomSession {
    struct App: Hashable, Sendable {
        var bundleID: String
        var name: String
        var url: URL?
    }

    enum Pick: Hashable, Sendable {
        case window(handle: Int)
        case app(App)
    }

    private(set) var revision = 0
    private(set) var isLoaded = false
    private(set) var pickable: [RoomLiveWindow] = []
    private(set) var picked: [Pick] = []
    private(set) var editingID: UUID?
    private(set) var roomName = ""
    @ObservationIgnored private(set) var snapshot: RoomWindowSweep.Snapshot?

    func present(_ snapshot: RoomWindowSweep.Snapshot, parked: Set<UInt32>) {
        self.snapshot = snapshot
        pickable = snapshot.windows.sorted { lhs, rhs in
            let left = Self.pickingTier(lhs, parked: parked)
            let right = Self.pickingTier(rhs, parked: parked)
            return left != right ? left < right : (lhs.frontRank, lhs.handle) < (rhs.frontRank, rhs.handle)
        }
        isLoaded = true
        revision &+= 1
    }

    func beginPicking(named name: String, editing id: UUID?, picked picks: [Pick]) {
        roomName = name
        editingID = id
        picked = picks
    }

    func togglePick(_ pick: Pick) {
        if let index = picked.firstIndex(of: pick) {
            picked.remove(at: index)
        } else {
            picked.append(pick)
        }
    }

    func reset() {
        snapshot = nil
        pickable = []
        picked = []
        editingID = nil
        roomName = ""
        isLoaded = false
    }

    private static func pickingTier(_ window: RoomLiveWindow, parked: Set<UInt32>) -> Int {
        if window.isAppHidden || window.isMinimized { return 2 }
        return window.windowID.map(parked.contains) == true ? 1 : 0
    }
}
