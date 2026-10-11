import AppKit

enum NoteCheckboxGeometry {
    static func slot(bodyPointSize: CGFloat) -> CGFloat {
        (Theme.Size.markdownListMarker * bodyPointSize / NSFont.systemFontSize).rounded()
    }

    static func rect(level: Int, firstLineHeight: CGFloat, bodyPointSize: CGFloat) -> CGRect {
        let side = bodyPointSize.rounded()
        let slot = slot(bodyPointSize: bodyPointSize)
        return CGRect(
            x: CGFloat(level) * slot + (slot - side) / 2, y: (firstLineHeight - side) / 2,
            width: side, height: side)
    }
}
