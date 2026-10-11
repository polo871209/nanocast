// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import Foundation

enum RoomWindowMatcher {
    static func assign(
        _ windows: [RoomWindow], to live: [RoomLiveWindow], claimed: Set<UInt32> = []
    ) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var used = Set<Int>()
        func pass(_ accepts: (RoomWindow, RoomLiveWindow) -> Bool) {
            for (index, window) in windows.enumerated() where result[index] == nil {
                guard
                    let match = live.indices.first(where: {
                        !used.contains($0) && live[$0].bundleID == window.bundleID
                            && accepts(window, live[$0])
                    })
                else { continue }
                result[index] = match
                used.insert(match)
            }
        }
        pass { saved, open in saved.windowID != nil && saved.windowID == open.windowID }
        pass { saved, open in !saved.title.isEmpty && saved.title == open.title }
        pass { saved, open in
            isSimilar(saved.title, open.title) && !isClaimed(open, by: claimed)
        }
        pass { _, open in !isClaimed(open, by: claimed) }
        pass { _, _ in true }
        return result
    }

    static func isSimilar(_ lhs: String, _ rhs: String) -> Bool {
        let left = folded(lhs)
        let right = folded(rhs)
        guard left.count >= 4, right.count >= 4 else { return false }
        if left.contains(right) || right.contains(left) { return true }
        let common = zip(left, right).prefix { $0 == $1 }.count
        return common >= min(12, min(left.count, right.count) * 2 / 3)
    }

    private static func isClaimed(_ window: RoomLiveWindow, by claimed: Set<UInt32>) -> Bool {
        window.windowID.map(claimed.contains) ?? false
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
