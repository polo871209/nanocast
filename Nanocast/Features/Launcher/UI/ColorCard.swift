import SwiftUI

struct ColorCard: View {
    @Environment(\.metrics) private var metrics
    let color: ColorValue
    let selected: Bool

    private static let swatchWidth: CGFloat = 108

    private var primary: ColorFormat { ColorFormat.primary(for: color) }

    var body: some View {
        HStack(spacing: 0) {
            LeadCardColumn(
                text: AttributedString(primary.string(for: color)), badge: primary.title)
            Image(systemName: "arrow.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tertiary)
            ColorSwatch(color: color, cornerRadius: metrics.radius.card)
                .frame(width: Self.swatchWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, metrics.spacing.md)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xxxl)
        .leadCard(selected: selected)
    }
}

@MainActor
enum ColorActionsMenu {
    static func content(color: ColorValue, core: AppCore) -> PopoverMenuContent {
        let primary = ColorFormat.primary(for: color)
        return PopoverMenuContent(
            header: "Copy Color as…",
            items: ColorFormat.offered(for: color).map { format in
                PopoverMenuItem(
                    title: format.title, icon: .blank,
                    shortcut: format == primary ? "↵" : nil, detail: format.string(for: color)
                ) {
                    core.clipboardCoordinator.copyColor(color, as: format)
                }
            })
    }
}
