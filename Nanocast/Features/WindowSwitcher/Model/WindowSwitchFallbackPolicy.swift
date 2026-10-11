import CoreGraphics

struct ServerWindow: Sendable {
    let id: UInt32
    let pid: Int32
    let layer: Int
    let alpha: Double
    let frame: CGRect
    let title: String
}

enum WindowSwitchFallbackPolicy {
    private static let minimumSide: CGFloat = 100

    /// One window per frame: Lark draws a meeting window as two server windows with equal bounds.
    static func unlisted(
        _ onScreen: [ServerWindow], of pid: Int32, reported: Set<UInt32>
    ) -> [ServerWindow] {
        let owned = onScreen.filter { $0.pid == pid && $0.layer == 0 && $0.alpha > 0 }
        let reportedFrames = owned.filter { reported.contains($0.id) }.map(\.frame)
        var unlisted: [ServerWindow] = []
        for window in owned
        where !reported.contains(window.id) && !reportedFrames.contains(window.frame)
            && min(window.frame.width, window.frame.height) >= minimumSide
        {
            guard let twin = unlisted.firstIndex(where: { $0.frame == window.frame }) else {
                unlisted.append(window)
                continue
            }
            if unlisted[twin].title.isEmpty { unlisted[twin] = window }
        }
        return unlisted
    }
}
