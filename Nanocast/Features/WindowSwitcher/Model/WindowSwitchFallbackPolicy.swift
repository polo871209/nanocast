import Foundation

struct ServerWindow: Sendable {
    let id: UInt32
    let pid: Int32
    let layer: Int
    let alpha: Double
    let size: CGSize
    let title: String
}

enum WindowSwitchFallbackPolicy {
    private static let minimumSide: CGFloat = 100

    static func unlisted(
        _ onScreen: [ServerWindow], of pid: Int32, reported: Set<UInt32>
    ) -> [ServerWindow] {
        onScreen.filter {
            $0.pid == pid && $0.layer == 0 && $0.alpha > 0 && !reported.contains($0.id)
                && min($0.size.width, $0.size.height) >= minimumSide
        }
    }
}
