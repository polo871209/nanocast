import SwiftUI

extension View {
    func screenshotChrome(_ metrics: InterfaceMetrics) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.barControl + metrics.spacing.xs, style: .continuous)
        // Behind the buttons, not around them: glass clips content, tooltips draw outside it.
        return background {
            shape.fill(Theme.Colors.panelScrim).background(GlassEffectView()).clipShape(shape)
        }
        .overlay { shape.strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline) }
        .environment(\.metrics, metrics)
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}
