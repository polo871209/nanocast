import AppKit
import SwiftUI

@MainActor
enum AnnotationAppearance {
    static func metrics(scale: CGFloat) -> AnnotationMetrics {
        let markup = Theme.Markup.self
        return AnnotationMetrics(
            scale: scale,
            points: AnnotationMetrics.Points(
                strokes: markup.strokes, highlighters: markup.highlighters, textSizes: markup.textSizes,
                brushes: markup.brushes, stepInset: markup.stepInset, mosaicBlock: markup.mosaicBlock,
                blurBlock: markup.blurBlock, hitSlop: markup.hitSlop, dragSlop: markup.dragSlop,
                selectionOutset: markup.selectionOutset),
            measureText: { AnnotationText.size(of: $0, fontSize: $1) })
    }

    static func painter(scale: CGFloat, mosaic: MosaicSource?) -> AnnotationPainter {
        let inks = Dictionary(uniqueKeysWithValues: AnnotationStyle.Ink.allCases.map { ($0, cgColor(color($0))) })
        return AnnotationPainter(
            metrics: metrics(scale: scale),
            palette: AnnotationPainter.Palette(
                inks: inks, highlighterAlpha: Theme.Markup.highlighterOpacity,
                lightText: cgColor(Theme.Colors.markupWhite), darkText: cgColor(Theme.Colors.markupBlack),
                rim: cgColor(Theme.Colors.markupWhite)),
            mosaic: mosaic)
    }

    static func color(_ ink: AnnotationStyle.Ink) -> Color {
        switch ink {
        case .red: return Theme.Colors.markupRed
        case .yellow: return Theme.Colors.markupYellow
        case .green: return Theme.Colors.markupGreen
        case .blue: return Theme.Colors.markupBlue
        case .black: return Theme.Colors.markupBlack
        case .white: return Theme.Colors.markupWhite
        }
    }

    static func title(_ ink: AnnotationStyle.Ink) -> String {
        switch ink {
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .black: return "Black"
        case .white: return "White"
        }
    }

    private static func cgColor(_ color: Color) -> CGColor { NSColor(color).cgColor }
}
