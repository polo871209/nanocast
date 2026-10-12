import CoreGraphics

struct AnnotationMetrics: Sendable {
    struct Points: Sendable {
        var strokes: [CGFloat]
        var highlighters: [CGFloat]
        var textSizes: [CGFloat]
        var brushes: [CGFloat]
        var stepInset: CGFloat
        var mosaicBlock: CGFloat
        var blurBlock: CGFloat
        var hitSlop: CGFloat
        var dragSlop: CGFloat
        var selectionOutset: CGFloat
    }

    let scale: CGFloat
    let points: Points
    let measureText: @Sendable (_ text: String, _ fontSize: CGFloat) -> CGSize

    func stroke(_ width: AnnotationStyle.Width) -> CGFloat { points.strokes[width.rawValue] * scale }
    func highlighter(_ width: AnnotationStyle.Width) -> CGFloat { points.highlighters[width.rawValue] * scale }
    func textSize(_ level: AnnotationStyle.Level) -> CGFloat { points.textSizes[level.rawValue] * scale }
    func brush(_ level: AnnotationStyle.Level) -> CGFloat { points.brushes[level.rawValue] * scale }
    var stepInset: CGFloat { points.stepInset * scale }
    var mosaicBlock: Int { max(Int((points.mosaicBlock * scale).rounded()), 1) }
    var blurBlock: Int { max(Int((points.blurBlock * scale).rounded()), 1) }
    var hitSlop: CGFloat { points.hitSlop * scale }
    var dragSlop: CGFloat { points.dragSlop * scale }
    var selectionOutset: CGFloat { points.selectionOutset * scale }
}
