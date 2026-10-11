import CoreGraphics

enum SelectionReveal {
    enum Edge {
        case top
        case bottom
    }

    private static let tolerance: CGFloat = 0.5

    static func edge(rowTop: CGFloat, rowBottom: CGFloat, band: CGFloat) -> Edge? {
        if rowBottom - rowTop >= band {
            return rowTop < -tolerance || rowTop > tolerance ? .top : nil
        }
        if rowTop < -tolerance { return .top }
        if rowBottom > band + tolerance { return .bottom }
        return nil
    }
}
