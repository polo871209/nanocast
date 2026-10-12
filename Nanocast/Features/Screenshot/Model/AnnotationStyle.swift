struct AnnotationStyle: Equatable, Sendable {
    enum Ink: CaseIterable, Sendable {
        case red, yellow, green, blue, black, white

        var isLight: Bool { self == .yellow || self == .white }
    }

    enum Level: Int, CaseIterable, Sendable {
        case small, medium, large
    }

    enum Width: Int, CaseIterable, Sendable {
        case extraThin, thin, medium, thick
    }

    enum MosaicEffect: CaseIterable, Sendable {
        case pixelate, blur
    }

    var ink = Ink.red
    var stroke = Width.thin
    var highlighter = Width.medium
    var highlighterFreehand = false
    var textSize = Level.medium
    var mosaicEffect = MosaicEffect.pixelate
    var mosaicBrush = true
    var brush = Level.medium
}
