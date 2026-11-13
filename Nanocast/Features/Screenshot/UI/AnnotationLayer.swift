import QuartzCore

final class AnnotationLayer: CALayer {
    struct Content: Equatable {
        var marks: [Annotation] = []
        var region: CGRect = .zero
        var hiddenText: Int?
    }

    var painter: AnnotationPainter?
    var content = Content() {
        didSet { if content != oldValue { setNeedsDisplay() } }
    }

    override init() {
        super.init()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func action(forKey event: String) -> CAAction? { nil }

    /// Core Animation hands a top-left context in points, because the canvas is flipped.
    override func draw(in context: CGContext) {
        guard let painter, !content.marks.isEmpty else { return }
        context.scaleBy(x: 1 / painter.metrics.scale, y: 1 / painter.metrics.scale)
        context.translateBy(x: -content.region.minX, y: -content.region.minY)
        painter.paintMarks(content.marks, in: context, hiddenText: content.hiddenText)
    }
}
