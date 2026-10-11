import CoreGraphics

struct CalloutPlacement: Equatable {
    enum CaretEdge: Equatable {
        case top
        case bottom
    }

    let center: CGPoint
    let caretEdge: CaretEdge
    let caretX: CGFloat

    static func resolve(
        field: CGRect, container: CGSize, size: CGSize, gap: CGFloat, inset: CGFloat,
        cornerRadius: CGFloat, caretWidth: CGFloat
    ) -> CalloutPlacement {
        let above = field.minY >= size.height + gap
        let half = size.width / 2

        let lower = half + inset
        let centerX = min(max(field.midX, lower), max(container.width - half - inset, lower))
        let centerY =
            above
            ? field.minY - gap - size.height / 2
            : field.maxY + gap + size.height / 2

        let limit = cornerRadius + caretWidth / 2
        let tip = field.midX - (centerX - half)

        return CalloutPlacement(
            center: CGPoint(x: centerX, y: centerY),
            caretEdge: above ? .bottom : .top,
            caretX: min(max(tip, limit), max(size.width - limit, limit))
        )
    }
}
