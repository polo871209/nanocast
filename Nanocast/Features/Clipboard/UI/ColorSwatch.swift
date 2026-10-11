import SwiftUI

struct ColorSwatch: View {
    @Environment(\.metrics) private var metrics
    let color: ColorValue
    var cornerRadius: CGFloat?

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius ?? metrics.radius.thumbnail, style: .continuous)
        shape
            .fill(Theme.Colors.controlSurface)
            .overlay { if color.hasAlpha { CheckerboardPattern().clipShape(shape) } }
            .overlay { shape.fill(color.swiftUIColor) }
            .overlay { shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1) }
            .accessibilityElement()
            .accessibilityLabel(ColorFormat.primary(for: color).string(for: color))
    }
}

private struct CheckerboardPattern: View {
    private static let cell: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)), with: .color(Theme.Colors.checkerLight))
            let columns = Int((size.width / Self.cell).rounded(.up))
            let rows = Int((size.height / Self.cell).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * Self.cell, y: CGFloat(row) * Self.cell,
                                width: Self.cell, height: Self.cell)),
                        with: .color(Theme.Colors.checkerDark))
                }
            }
        }
        .drawingGroup()
    }
}

extension ColorValue {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
