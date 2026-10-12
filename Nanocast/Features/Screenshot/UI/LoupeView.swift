import AppKit
import SwiftUI

final class LoupeView: NSView {
    private static let samples = 15
    private static let side = CGFloat(samples) * Theme.Size.loupeCell
    static let size = CGSize(width: side, height: side + Theme.Size.loupeCaption)

    private let zoom = CALayer()
    private let grid = CAShapeLayer()
    private let target = CAShapeLayer()
    private let caption = CATextLayer()
    private let imageSize: CGSize

    init(image: CGImage, scale: CGFloat) {
        imageSize = CGSize(width: image.width, height: image.height)
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        wantsLayer = true
        guard let layer else { return }
        layer.cornerRadius = Theme.Radius.loupe
        layer.masksToBounds = true
        layer.borderWidth = Theme.Size.hairline
        zoom.contents = image
        zoom.magnificationFilter = .nearest
        zoom.frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        grid.path = Self.gridPath()
        grid.lineWidth = Theme.Size.hairline
        grid.fillColor = nil
        target.path = CGPath(rect: Self.cell(at: Self.samples / 2), transform: nil)
        target.lineWidth = Theme.Size.hairline
        target.fillColor = nil
        caption.frame = CGRect(
            x: 0, y: Self.side + Theme.Spacing.xs, width: Self.side,
            height: Theme.Size.loupeCaption - Theme.Spacing.xs)
        caption.contentsScale = scale
        caption.alignmentMode = .center
        caption.isWrapped = true
        caption.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        caption.fontSize = NSFont.smallSystemFontSize
        for sublayer in [zoom, grid, target, caption] { layer.addSublayer(sublayer) }
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    func show(pixel: PixelPoint, caption text: String) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let first = CGPoint(x: pixel.x - Self.samples / 2, y: pixel.y - Self.samples / 2)
        zoom.contentsRect = CGRect(
            x: first.x / imageSize.width, y: first.y / imageSize.height,
            width: CGFloat(Self.samples) / imageSize.width, height: CGFloat(Self.samples) / imageSize.height)
        caption.string = text
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor(Theme.Colors.loupeSurface).cgColor
            layer?.borderColor = NSColor(Theme.Colors.border).cgColor
            grid.strokeColor = NSColor(Theme.Colors.loupeGrid).cgColor
            target.strokeColor = NSColor(Theme.Colors.captureHandleRim).cgColor
            caption.foregroundColor = NSColor(Theme.Colors.textPrimary).cgColor
        }
    }

    private static func cell(at index: Int) -> CGRect {
        let origin = CGFloat(index) * Theme.Size.loupeCell
        return CGRect(x: origin, y: origin, width: Theme.Size.loupeCell, height: Theme.Size.loupeCell)
    }

    private static func gridPath() -> CGPath {
        let path = CGMutablePath()
        for index in 1..<samples {
            let offset = CGFloat(index) * Theme.Size.loupeCell
            path.move(to: CGPoint(x: offset, y: 0))
            path.addLine(to: CGPoint(x: offset, y: side))
            path.move(to: CGPoint(x: 0, y: offset))
            path.addLine(to: CGPoint(x: side, y: offset))
        }
        return path
    }
}
