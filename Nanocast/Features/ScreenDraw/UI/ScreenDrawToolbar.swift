import SwiftUI

struct ScreenDrawToolbar: View {
    struct Actions {
        let choose: (DrawTool) -> Void
        let pick: (AnnotationStyle.Ink) -> Void
        let undo: () -> Void
        let clear: () -> Void
        let hide: () -> Void
        let end: () -> Void
    }

    let session: ScreenDrawSession
    let metrics: InterfaceMetrics
    let actions: Actions

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            SymbolImage(name: "line.3.horizontal", size: glyph)
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: glyph, height: metrics.size.barButtonHeight)
                .windowDraggable(true)
                .accessibilityLabel("Move the bar")
            ScreenshotToolbarDivider()
            ForEach(DrawTool.allCases, id: \.self) { tool in
                ScreenDrawButton(title: tool.title, hint: tool.key.uppercased(), isSelected: session.tool == tool) {
                    actions.choose(tool)
                } label: {
                    symbol(tool.symbol)
                }
            }
            ScreenshotToolbarDivider()
            ForEach(AnnotationStyle.Ink.allCases, id: \.self) { ink in
                ScreenDrawButton(
                    title: AnnotationAppearance.title(ink), hint: String(DrawKey.digit(for: ink)),
                    isSelected: session.ink == ink && session.tool != .eraser
                ) {
                    actions.pick(ink)
                } label: {
                    InkSwatch(ink: ink)
                }
            }
            ScreenshotToolbarDivider()
            ScreenDrawButton(title: "Undo", hint: "⌘Z", isEnabled: session.canUndo, action: actions.undo) {
                symbol("arrow.uturn.backward", isEnabled: session.canUndo)
            }
            ScreenDrawButton(title: "Clear", hint: "⌫", isEnabled: session.hasMarks, action: actions.clear) {
                symbol("trash", isEnabled: session.hasMarks)
            }
            ScreenDrawButton(title: "Hide the bar", hint: "⇥", action: actions.hide) {
                symbol("eye.slash")
            }
            ScreenDrawButton(title: "Stop drawing", hint: "esc", action: actions.end) {
                symbol("xmark", tint: Theme.Colors.destructive)
            }
        }
        .padding(metrics.spacing.xs)
        .screenshotChrome(metrics)
        .accessibilityLabel("Draw on screen")
    }

    private var glyph: CGFloat { metrics.scaled(Theme.Size.noteGlyph) }

    private func symbol(_ name: String, tint: Color = Theme.Colors.textPrimary, isEnabled: Bool = true) -> some View {
        SymbolImage(name: name, size: glyph)
            .foregroundStyle(isEnabled ? tint : Theme.Colors.textTertiary)
    }
}

private struct ScreenDrawButton<Label: View>: View {
    let title: String
    let hint: String
    var isSelected = false
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder let label: Label
    @Environment(\.metrics) private var metrics

    var body: some View {
        let glyph = metrics.scaled(Theme.Size.noteGlyph)
        BarButton(chrome: .rounded, isSelected: isSelected, isCompact: true, action: action) {
            label
                .frame(width: glyph, height: glyph)
                .overlay(alignment: .bottomTrailing) {
                    Text(hint)
                        .font(.system(size: metrics.scaled(Theme.Markup.keyHint), weight: .medium))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .fixedSize()
                        .offset(x: metrics.spacing.sm, y: metrics.spacing.xs)
                }
        }
        .disabled(!isEnabled)
        .focusable(false)
        .accessibilityLabel(title)
        .accessibilityValue(hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
