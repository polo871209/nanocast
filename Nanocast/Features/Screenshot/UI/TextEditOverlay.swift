import AppKit

final class TextEditOverlay: NSTextView {
    /// A throwaway text view on the window's undo manager crashes the next ⌘Z after it is freed.
    private let ownUndoManager = UndoManager()
    private let changed: (String) -> Void
    private let finished: () -> Void

    init(
        text: String, font: NSFont, color: NSColor, origin: CGPoint, changed: @escaping (String) -> Void,
        finished: @escaping () -> Void
    ) {
        self.changed = changed
        self.finished = finished
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        super.init(frame: CGRect(origin: origin, size: .zero), textContainer: container)
        isRichText = false
        allowsUndo = true
        drawsBackground = false
        textContainerInset = .zero
        isHorizontallyResizable = true
        isVerticallyResizable = true
        maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        self.font = font
        textColor = color
        insertionPointColor = color
        typingAttributes = [.font: font, .foregroundColor: color]
        string = text
        fitText()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var undoManager: UndoManager? { ownUndoManager }

    func restyle(font: NSFont, color: NSColor) {
        guard self.font != font || textColor != color else { return }
        self.font = font
        textColor = color
        insertionPointColor = color
        typingAttributes = [.font: font, .foregroundColor: color]
        fitText()
    }

    override func cancelOperation(_ sender: Any?) {
        finished()
    }

    override func didChangeText() {
        super.didChangeText()
        fitText()
        changed(string)
    }

    private func fitText() {
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let caret = font.map(layoutManager.defaultLineHeight) ?? used.height
        setFrameSize(CGSize(width: max(used.width.rounded(.up), 2), height: max(used.height.rounded(.up), caret)))
    }
}
