import Foundation

enum WindowSwitchOrder {
    static func sorted(_ entries: [WindowSwitchEntry], recency: [Int32]) -> [WindowSwitchEntry] {
        let rank = Dictionary(recency.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        return entries.sorted { left, right in
            let leftRank = rank[left.pid] ?? .max
            let rightRank = rank[right.pid] ?? .max
            if leftRank != rightRank { return leftRank < rightRank }
            if left.pid != right.pid {
                let order = left.appName.localizedCaseInsensitiveCompare(right.appName)
                return order == .orderedSame ? left.pid < right.pid : order == .orderedAscending
            }
            return left.handle < right.handle
        }
    }

    static func initialSelection(
        in entries: [WindowSwitchEntry], frontmost: Int32?, backward: Bool
    ) -> Int {
        guard entries.count > 1 else { return 0 }
        if backward { return entries.count - 1 }
        return entries.firstIndex { $0.pid != frontmost } ?? 1
    }
}
