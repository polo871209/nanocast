import CoreGraphics

enum ChromePlacement {
    static func toolbar(size: CGSize, area: CGRect, in bounds: CGRect, gap: CGFloat) -> CGRect {
        let y: CGFloat
        if area.maxY + gap + size.height <= bounds.maxY - gap {
            y = area.maxY + gap
        } else if area.minY - gap - size.height >= bounds.minY + gap {
            y = area.minY - gap - size.height
        } else {
            y = max(area.maxY - gap - size.height, bounds.minY + gap)
        }
        return CGRect(origin: CGPoint(x: clampedX(area.maxX - size.width, size, bounds, gap), y: y), size: size)
    }

    static func optionsBar(size: CGSize, toolbar: CGRect, in bounds: CGRect, gap: CGFloat) -> CGRect {
        let below = toolbar.maxY + gap
        let y = below + size.height <= bounds.maxY - gap ? below : toolbar.minY - gap - size.height
        return CGRect(origin: CGPoint(x: clampedX(toolbar.minX, size, bounds, gap), y: y), size: size)
    }

    static func sizePill(size: CGSize, area: CGRect, in bounds: CGRect, gap: CGFloat) -> CGRect {
        let above = area.minY - gap - size.height
        let y = above >= bounds.minY + gap ? above : area.minY + gap
        return CGRect(origin: CGPoint(x: clampedX(area.minX, size, bounds, gap), y: y), size: size)
    }

    static func loupe(size: CGSize, cursor: CGPoint, in bounds: CGRect, offset: CGFloat) -> CGRect {
        var x = cursor.x + offset
        if x + size.width > bounds.maxX { x = cursor.x - offset - size.width }
        var y = cursor.y + offset
        if y + size.height > bounds.maxY { y = cursor.y - offset - size.height }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func clampedX(_ x: CGFloat, _ size: CGSize, _ bounds: CGRect, _ gap: CGFloat) -> CGFloat {
        min(max(x, bounds.minX + gap), bounds.maxX - gap - size.width)
    }
}
