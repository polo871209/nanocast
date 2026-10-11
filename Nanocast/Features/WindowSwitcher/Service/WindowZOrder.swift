import CoreGraphics

@MainActor
enum WindowZOrder {
    private static let normalLayer = 0

    static func appRanks() -> [pid_t: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var ranks: [pid_t: Int] = [:]
        for window in listing {
            guard window[kCGWindowLayer as String] as? Int == normalLayer,
                let pid = window[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            if ranks[pid] == nil { ranks[pid] = ranks.count }
        }
        return ranks
    }
}
