import SwiftUI

struct SelectionSizePill: View {
    let metrics: InterfaceMetrics
    let size: String
    let showsPixels: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Text(size)
                .font(metrics.typography.keyCap.monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, metrics.spacing.sm)
                .padding(.vertical, metrics.spacing.xxs)
                .background {
                    Capsule().fill(Theme.Colors.panelScrim).background(GlassEffectView()).clipShape(Capsule())
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .tooltip(showsPixels ? "Show points" : "Show pixels", alignment: .leading)
        .accessibilityLabel(size)
        .accessibilityHint(showsPixels ? "Shows the size in points" : "Shows the size in pixels")
        .environment(\.metrics, metrics)
        .fixedSize()
    }
}
