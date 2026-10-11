import SwiftUI

private struct HeaderMenuSymbol: View {
    let name: String
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        if let image = NSImage(
            systemSymbolName: SystemSymbolName.resolve(name, isDark: colorScheme == .dark),
            accessibilityDescription: nil
        )?
        .withSymbolConfiguration(configuration) {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(width: size, height: size)
        }
    }
}

enum BarButtonChrome {
    case capsule
    case rounded

    func shape(_ metrics: InterfaceMetrics) -> AnyShape {
        switch self {
        case .capsule:
            return AnyShape(Capsule())
        case .rounded:
            return AnyShape(
                RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous))
        }
    }
}

struct BarButton<Label: View>: View {
    var chrome: BarButtonChrome = .capsule
    var isSelected = false
    var isCompact = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        let shape = chrome.shape(metrics)
        return Button(action: action) {
            label
                .padding(.horizontal, isCompact ? metrics.spacing.sm : metrics.spacing.md)
                .frame(height: metrics.size.barButtonHeight)
                .contentShape(shape)
                .background(shape.fill(fill))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var fill: Color {
        if isSelected { return Theme.Colors.selection }
        return hovered ? Theme.Colors.rowHover : Color.clear
    }
}

struct HeaderMenuButton: View {
    let title: String
    let systemImage: String
    let isOpen: Bool
    let help: String
    let action: () -> Void
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BarButton(chrome: .rounded, action: action) {
            HStack(spacing: metrics.spacing.sm) {
                HeaderMenuSymbol(name: systemImage, size: metrics.scaled(Theme.Typography.menuSymbolSize))
                Text(title)
                    .font(metrics.typography.bar)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(metrics.typography.disclosure)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .help(help)
    }
}
