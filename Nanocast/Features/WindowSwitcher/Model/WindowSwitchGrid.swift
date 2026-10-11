import Foundation

struct WindowSwitchGrid: Equatable, Sendable {
    let columns: Int
    let scale: Double

    static func fit(
        count: Int, tile: CGSize, gap: Double, padding: Double, bounds: CGSize, minimumScale: Double
    ) -> WindowSwitchGrid {
        guard count > 0 else { return WindowSwitchGrid(columns: 1, scale: 1) }
        let fitting = Int((bounds.width - 2 * padding + gap) / (tile.width + gap))
        let columns = min(count, max(1, fitting))
        let rows = Double((count + columns - 1) / columns)
        let height = 2 * padding + rows * tile.height + (rows - 1) * gap
        let scale = min(1, max(minimumScale, bounds.height / height))
        return WindowSwitchGrid(columns: columns, scale: scale)
    }
}
