import SwiftUI

struct ToolOptionsBar: View {
    let tool: ScreenshotTool
    let session: ScreenshotSession
    let metrics: InterfaceMetrics
    let edit: (MarkupCommand) -> Void

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            switch tool {
            case .rectangle, .ellipse, .line, .arrow, .pen:
                sizes(\.stroke, titles: Self.widthTitles) { StrokeDot(size: Theme.Markup.widthDots[$0.rawValue]) }
                ScreenshotToolbarDivider()
                inks
            case .highlighter:
                toggle(\.highlighterFreehand, off: ("line.diagonal", "Straight"), on: ("scribble", "Freehand"))
                ScreenshotToolbarDivider()
                sizes(\.highlighter, titles: Self.widthTitles) {
                    StrokeDot(size: Theme.Markup.widthDots[$0.rawValue])
                }
                ScreenshotToolbarDivider()
                inks
            case .text, .step:
                sizes(\.textSize, titles: ["Small", "Medium", "Large"]) { TextSizeGlyph(level: $0) }
                ScreenshotToolbarDivider()
                inks
            case .mosaic:
                toggle(\.mosaicBrush, off: ("rectangle.dashed", "Box"), on: ("scribble", "Brush"))
                ScreenshotToolbarDivider()
                choice(\.mosaicEffect, .pixelate, symbol: "ScreenshotMosaic", title: "Pixelate")
                choice(\.mosaicEffect, .blur, symbol: "drop", title: "Blur")
                ScreenshotToolbarDivider()
                sizes(\.brush, titles: ["Small brush", "Medium brush", "Large brush"], isEnabled: session.style.mosaicBrush) {
                    StrokeDot(size: Theme.Markup.levelDots[$0.rawValue])
                }
            }
        }
        .padding(metrics.spacing.xs)
        .screenshotChrome(metrics)
        .accessibilityLabel("\(tool.title) options")
    }

    private var inks: some View {
        ForEach(AnnotationStyle.Ink.allCases, id: \.self) { ink in
            OptionButton(title: AnnotationAppearance.title(ink), isSelected: session.style.ink == ink) {
                restyle(\.ink, ink)
            } label: {
                InkSwatch(ink: ink)
            }
        }
    }

    private static let widthTitles = ["Extra thin", "Thin", "Medium", "Thick"]

    private func sizes<Size: CaseIterable & Hashable & RawRepresentable<Int>, Label: View>(
        _ keyPath: WritableKeyPath<AnnotationStyle, Size>, titles: [String], isEnabled: Bool = true,
        @ViewBuilder label: @escaping (Size) -> Label
    ) -> some View where Size.AllCases: RandomAccessCollection {
        ForEach(Size.allCases, id: \.self) { size in
            OptionButton(
                title: titles[size.rawValue], isSelected: isEnabled && session.style[keyPath: keyPath] == size,
                isEnabled: isEnabled
            ) {
                restyle(keyPath, size)
            } label: {
                label(size)
            }
        }
    }

    private func toggle(
        _ keyPath: WritableKeyPath<AnnotationStyle, Bool>, off: (symbol: String, title: String),
        on: (symbol: String, title: String)
    ) -> some View {
        ForEach([false, true], id: \.self) { value in
            let option = value ? on : off
            OptionButton(title: option.title, isSelected: session.style[keyPath: keyPath] == value) {
                restyle(keyPath, value)
            } label: {
                OptionSymbol(name: option.symbol)
            }
        }
    }

    private func choice<Value: Equatable>(
        _ keyPath: WritableKeyPath<AnnotationStyle, Value>, _ value: Value, symbol: String, title: String
    ) -> some View {
        OptionButton(title: title, isSelected: session.style[keyPath: keyPath] == value) {
            restyle(keyPath, value)
        } label: {
            OptionSymbol(name: symbol)
        }
    }

    private func restyle<Value>(_ keyPath: WritableKeyPath<AnnotationStyle, Value>, _ value: Value) {
        var style = session.style
        style[keyPath: keyPath] = value
        edit(.restyle(style))
    }
}

private struct OptionButton<Label: View>: View {
    let title: String
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder let label: Label
    @Environment(\.metrics) private var metrics

    var body: some View {
        BarButton(chrome: .rounded, isSelected: isSelected, isCompact: true, action: action) {
            label
                .foregroundStyle(isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                .frame(minWidth: metrics.scaled(Theme.Size.noteGlyph), minHeight: metrics.scaled(Theme.Size.noteGlyph))
        }
        .disabled(!isEnabled)
        .focusable(false)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .tooltip(title)
    }
}

private struct OptionSymbol: View {
    let name: String
    @Environment(\.metrics) private var metrics

    var body: some View {
        SymbolImage(name: name, size: metrics.scaled(Theme.Size.noteGlyph))
    }
}

private struct StrokeDot: View {
    let size: CGFloat
    @Environment(\.metrics) private var metrics

    var body: some View {
        Circle().frame(width: metrics.scaled(size), height: metrics.scaled(size))
    }
}

private struct TextSizeGlyph: View {
    let level: AnnotationStyle.Level
    @Environment(\.metrics) private var metrics

    var body: some View {
        Text("A").font(.system(size: metrics.scaled(Theme.Markup.levelText[level.rawValue]), weight: .semibold))
    }
}

private struct InkSwatch: View {
    let ink: AnnotationStyle.Ink
    @Environment(\.metrics) private var metrics

    var body: some View {
        let size = metrics.scaled(Theme.Markup.swatch)
        Circle()
            .fill(AnnotationAppearance.color(ink))
            .overlay { Circle().strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline) }
            .frame(width: size, height: size)
    }
}
