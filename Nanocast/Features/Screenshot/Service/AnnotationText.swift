import AppKit
import CoreText

enum AnnotationText {
    enum Face: Sendable {
        case standard, rounded
    }

    static func font(size: CGFloat, face: Face = .standard) -> NSFont {
        switch face {
        case .standard:
            return .systemFont(ofSize: size, weight: .semibold)
        case .rounded:
            let base = NSFont.systemFont(ofSize: size, weight: .medium)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        }
    }

    static func size(of text: String, fontSize: CGFloat, face: Face = .standard) -> CGSize {
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter(text, fontSize: fontSize, face: face, color: nil), CFRange(), nil,
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), nil)
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    static func draw(
        _ text: String, fontSize: CGFloat, face: Face = .standard, color: CGColor, at origin: CGPoint,
        in context: CGContext
    ) {
        let size = size(of: text, fontSize: fontSize, face: face)
        let frame = CTFramesetterCreateFrame(
            framesetter(text, fontSize: fontSize, face: face, color: color), CFRange(),
            CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), nil)
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y + size.height)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private static func framesetter(_ text: String, fontSize: CGFloat, face: Face, color: CGColor?) -> CTFramesetter {
        var attributes: [NSAttributedString.Key: Any] = [.font: font(size: fontSize, face: face)]
        if let color { attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color }
        return CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
