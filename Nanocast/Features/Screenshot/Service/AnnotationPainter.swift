import CoreGraphics

struct AnnotationPainter {
    struct Palette {
        let inks: [AnnotationStyle.Ink: CGColor]
        let highlighterAlpha: CGFloat
        let lightText: CGColor
        let darkText: CGColor
        let rim: CGColor
    }

    let metrics: AnnotationMetrics
    let palette: Palette
    let mosaic: MosaicSource?

    func paint(_ annotations: [Annotation], in context: CGContext, area: CGRect, hiddenText: Int? = nil) {
        context.saveGState()
        context.clip(to: area)
        paintMosaic(annotations, in: context)
        paintMarks(annotations, in: context, hiddenText: hiddenText)
        context.restoreGState()
    }

    func paintMarks(_ annotations: [Annotation], in context: CGContext, hiddenText: Int? = nil) {
        var step = 0
        for annotation in annotations where !annotation.isMosaic {
            if case .step = annotation.shape { step += 1 }
            paintMark(annotation, in: context, showsText: annotation.id != hiddenText, step: step)
        }
    }

    static func mosaicPath(
        _ annotations: [Annotation], effect: AnnotationStyle.MosaicEffect, metrics: AnnotationMetrics
    ) -> CGPath? {
        let shapes = annotations.compactMap { annotation -> CGPath? in
            guard annotation.style.mosaicEffect == effect else { return nil }
            switch annotation.shape {
            case .mosaicBox(let rect):
                return CGPath(rect: rect, transform: nil)
            case .mosaicStroke(let points):
                return polyline(points).copy(
                    strokingWithWidth: metrics.brush(annotation.style.brush), lineCap: .round, lineJoin: .round,
                    miterLimit: 10)
            default:
                return nil
            }
        }
        return shapes.dropFirst().reduce(shapes.first) { $0?.union($1) }
    }

    private func ink(_ annotation: Annotation) -> CGColor {
        palette.inks[annotation.style.ink] ?? palette.darkText
    }

    private func paintMosaic(_ annotations: [Annotation], in context: CGContext) {
        guard let mosaic else { return }
        for effect in AnnotationStyle.MosaicEffect.allCases {
            guard let path = Self.mosaicPath(annotations, effect: effect, metrics: metrics) else { continue }
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.interpolationQuality = effect == .pixelate ? .none : .high
            context.drawUpright(mosaic.image(for: effect), in: mosaic.bounds)
            context.restoreGState()
        }
    }

    private func paintMark(_ annotation: Annotation, in context: CGContext, showsText: Bool, step: Int) {
        let color = ink(annotation)
        let width = metrics.stroke(annotation.style.stroke)
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch annotation.shape {
        case .rectangle(let rect):
            context.setLineJoin(.miter)
            context.stroke(rect)
        case .ellipse(let rect):
            context.strokeEllipse(in: rect)
        case .line(let segment):
            context.strokeLineSegments(between: [segment.start, segment.end])
        case .arrow(let segment):
            let outline = AnnotationGeometry.arrowOutline(segment, width: width)
            guard !outline.isEmpty else { return }
            context.addLines(between: outline)
            context.closePath()
            context.fillPath()
        case .pen(let points):
            context.addPath(Self.smoothed(points))
            context.strokePath()
        case .highlighter(let points):
            context.setStrokeColor(color.copy(alpha: palette.highlighterAlpha) ?? color)
            context.setLineWidth(metrics.highlighter(annotation.style.highlighter))
            context.addPath(Self.smoothed(points))
            context.strokePath()
        case .text(let text, let origin):
            guard showsText else { return }
            AnnotationText.draw(
                text, fontSize: metrics.textSize(annotation.style.textSize), color: color, at: origin, in: context)
        case .step(let center):
            paintStep(annotation, number: step, center: center, in: context)
        case .mosaicBox, .mosaicStroke:
            return
        }
    }

    private func paintStep(_ annotation: Annotation, number: Int, center: CGPoint, in context: CGContext) {
        let style = annotation.style
        let circle = AnnotationGeometry.stepCircle(at: center, style: style, metrics: metrics)
        context.fillEllipse(in: circle)
        context.setStrokeColor(palette.rim)
        context.setLineWidth(metrics.scale * 1.5)
        context.strokeEllipse(in: circle)
        let label = "\(number)"
        let fontSize = metrics.textSize(style.textSize)
        let size = metrics.measureText(label, fontSize)
        AnnotationText.draw(
            label, fontSize: fontSize, color: style.ink.isLight ? palette.darkText : palette.lightText,
            at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), in: context)
    }

    private static func polyline(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        return path
    }

    private static func smoothed(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLines(between: points)
            return path
        }
        for index in 1..<(points.count - 1) {
            let point = points[index]
            let next = points[index + 1]
            path.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2), control: point)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}
