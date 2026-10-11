import CoreGraphics

enum HoverArming {
    private static let slop: CGFloat = 3

    static func isDeliberate(_ pointer: CGPoint, from anchor: CGPoint) -> Bool {
        hypot(pointer.x - anchor.x, pointer.y - anchor.y) > slop
    }
}
