import AppKit
import CoreText

enum AnnotationText {
    static func font(size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }

    static func size(of text: String, fontSize: CGFloat) -> CGSize {
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter(text, fontSize: fontSize, color: nil), CFRange(), nil,
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), nil)
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    static func draw(_ text: String, fontSize: CGFloat, color: CGColor, at origin: CGPoint, in context: CGContext) {
        let size = size(of: text, fontSize: fontSize)
        let frame = CTFramesetterCreateFrame(
            framesetter(text, fontSize: fontSize, color: color), CFRange(),
            CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), nil)
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y + size.height)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private static func framesetter(_ text: String, fontSize: CGFloat, color: CGColor?) -> CTFramesetter {
        var attributes: [NSAttributedString.Key: Any] = [.font: font(size: fontSize)]
        if let color { attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color }
        return CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
