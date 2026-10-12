import AppKit
import SwiftUI

final class CaptureCanvasView: NSView {
    private enum Key {
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let space: UInt16 = 49
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    private enum Gesture {
        case area
        case markup
    }

    /// Core Animation draws nothing past its largest texture, so a taller image shows in strips.
    private static let largestLayerPixels = 8192
    private static let stripPixels = 2048

    private let display: CapturedDisplay
    private let session: ScreenshotSession
    private let metrics: InterfaceMetrics
    private let changed: () -> Void
    private let perform: (ScreenshotIntent) -> Void
    private let imageLayer = CALayer()
    private let areaLayer = CALayer()
    private let windowLayer = CALayer()
    private let pixelateLayer = CALayer()
    private let pixelateMask = CAShapeLayer()
    private let blurLayer = CALayer()
    private let blurMask = CAShapeLayer()
    private let marksLayer = AnnotationLayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private let loupe: LoupeView
    private lazy var chromeMetrics = InterfaceMetrics(scale: metrics.scale * Theme.Markup.chromeScale)
    private lazy var toolbar = NSHostingView(
        rootView: ScreenshotToolbar(
            session: session, metrics: chromeMetrics, edit: { [weak self] in self?.apply($0) },
            perform: { [weak self] in self?.run($0) }))
    private lazy var toolbarSize = toolbar.fittingSize
    private lazy var optionsBar = NSHostingView(rootView: optionsBarView(for: .rectangle))
    private var optionsTool: ScreenshotTool?
    private var optionsSize = CGSize.zero
    private lazy var pill = NSHostingView(rootView: sizePill(""))
    private var pillText = ""
    private var pillSize = CGSize.zero
    private var textEditor: TextEditOverlay?
    private var gesture: Gesture?
    private var isPanning = false
    private var imageStrips: [CALayer] = []
    private var scrollObserver: NotificationToken?
    private weak var chromeHost: NSView?
    private var toolbarFrame = CGRect.zero

    init(
        display: CapturedDisplay, session: ScreenshotSession, metrics: InterfaceMetrics, chromeHost: NSView? = nil,
        changed: @escaping () -> Void, perform: @escaping (ScreenshotIntent) -> Void
    ) {
        self.chromeHost = chromeHost
        self.display = display
        self.session = session
        self.metrics = metrics
        self.changed = changed
        self.perform = perform
        loupe = LoupeView(image: display.image, scale: display.scale)
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))
        wantsLayer = true
        guard let layer else { return }
        imageLayer.contentsGravity = .resize
        imageLayer.frame = bounds
        if display.image.height > Self.largestLayerPixels {
            imageStrips = stride(from: 0, to: display.image.height, by: Self.stripPixels).map { y in
                let strip = CALayer()
                strip.contentsGravity = .resize
                strip.actions = ["contents": NSNull()]
                strip.frame = display.points(Self.strip(at: y, of: display.image))
                imageLayer.addSublayer(strip)
                return strip
            }
        } else {
            imageLayer.contents = display.image
        }
        areaLayer.masksToBounds = true
        pixelateLayer.magnificationFilter = .nearest
        pixelateLayer.mask = pixelateMask
        blurLayer.mask = blurMask
        marksLayer.contentsScale = display.scale
        marksLayer.needsDisplayOnBoundsChange = true
        marksLayer.painter = AnnotationAppearance.painter(scale: display.scale, mosaic: nil)
        for sublayer in [windowLayer, pixelateLayer, blurLayer, marksLayer] {
            sublayer.contentsGravity = .resize
            areaLayer.addSublayer(sublayer)
        }
        dimLayer.fillRule = .evenOdd
        borderLayer.fillColor = nil
        borderLayer.lineWidth = Theme.Size.captureBorder
        handlesLayer.lineWidth = Theme.Size.captureHandleRim
        selectionLayer.fillColor = nil
        selectionLayer.lineWidth = Theme.Size.captureBorder
        selectionLayer.lineDashPattern = Theme.Markup.selectionDash.map { NSNumber(value: Double($0)) }
        for sublayer in [imageLayer, areaLayer, dimLayer, borderLayer, handlesLayer, selectionLayer] {
            sublayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer.addSublayer(sublayer)
        }
        for chrome in [loupe, pill, optionsBar, toolbar] as [NSView] {
            chrome.isHidden = true
            (chromeHost ?? self).addSubview(chrome)
        }
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let clip = enclosingScrollView?.contentView else { return scrollObserver = nil }
        clip.postsBoundsChangedNotifications = true
        let token = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
        scrollObserver = NotificationToken(token, center: .default)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    func render() {
        let pixels = session.area.flatMap { $0.display == display.id ? $0.rect : nil }
        let area = pixels.map(display.points)
        let hover = session.area == nil ? session.hover.flatMap { $0.display == display.id ? $0.rect : nil } : nil
        let hole = area ?? hover.map(display.points)
        let visible = visibleRect
        let near = visible.insetBy(dx: -Theme.Size.captureHandle, dy: -Theme.Size.captureHandle)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderImageStrips()
        let dim = CGMutablePath()
        dim.addRect(visible)
        if let shown = hole?.intersection(visible), !shown.isNull { dim.addRect(shown) }
        dimLayer.path = dim
        let outset = -Theme.Size.captureBorder / 2
        let border = hole.map { $0.insetBy(dx: outset, dy: outset).intersection(near) }
        borderLayer.path = border.flatMap { $0.isNull ? nil : CGPath(rect: $0, transform: nil) }
        handlesLayer.path = session.tool == nil ? area.map { Self.handlesPath($0, near: near) } : nil
        renderMarkup(in: pixels)
        CATransaction.commit()
        renderLoupe()
        renderChrome(around: area)
        renderTextEditor()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = location(of: event)
        session.movePointer(to: point, on: display.id)
        cursor(at: point).set()
        changed()
    }

    override func mouseDown(with event: NSEvent) {
        let point = location(of: event)
        if let textEditor {
            guard session.grabEditingText(at: point, on: display) else { return endTextEdit() }
            gesture = .markup
            window?.makeFirstResponder(textEditor)
        } else if session.tool != nil {
            pressMarkup(at: point, clickCount: event.clickCount)
        } else if event.clickCount == 2, isInsideArea(point) {
            return run(.copy)
        } else {
            session.press(
                at: point, on: display.id, reach: Theme.Size.captureHandleReach, slop: Theme.Size.captureClickSlop)
            gesture = .area
        }
        cursor(at: point).set()
        changed()
    }

    override func mouseDragged(with event: NSEvent) {
        if gesture != nil { autoscroll(with: event) }
        let point = location(of: event)
        let shift = event.modifierFlags.contains(.shift)
        switch gesture {
        case .area: session.drag(to: point, square: shift, panning: isPanning)
        case .markup: session.dragAnnotation(to: point, on: display, constrained: shift)
        case nil: return
        }
        changed()
    }

    override func mouseUp(with event: NSEvent) {
        switch gesture {
        case .area: if session.release() { perform(.captureWindow) }
        case .markup:
            session.releaseAnnotation()
            beginTextEdit()
        case nil: break
        }
        gesture = nil
        cursor(at: location(of: event)).set()
        changed()
    }

    override func rightMouseDown(with event: NSEvent) {
        if textEditor != nil {
            endTextEdit()
        } else if let tool = session.tool {
            session.choose(tool)
        } else if session.area != nil {
            session.clearArea()
        } else {
            return perform(.cancel)
        }
        changed()
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let step = modifiers.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case Key.escape:
            run(session.area == nil ? .cancel : .copy)
        case Key.returnKey, Key.enter:
            if session.area != nil {
                run(.copy)
            } else if session.restoreLastArea() {
                changed()
            }
        case Key.space:
            isPanning = true
        case Key.delete, Key.forwardDelete:
            session.deleteSelectedAnnotation()
            changed()
        case Key.left, Key.right, Key.up, Key.down:
            guard session.tool == nil else { return }
            let (dx, dy) = Self.direction(event.keyCode)
            if modifiers.contains(.command) {
                session.grow(dx: dx * step, dy: dy * step)
            } else {
                session.nudge(dx: dx * step, dy: dy * step)
            }
            changed()
        default:
            guard modifiers.subtracting(.shift).isEmpty, let key = character(of: event)?.first else { return }
            if session.area != nil, modifiers.isEmpty, let tool = ScreenshotTool(key: key) {
                apply(.choose(tool))
            } else if key == "c", session.tool == nil, let color = session.colorUnderPointer() {
                perform(.copyColor(color.hex))
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == Key.space { isPanning = false }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard event.type == .keyDown, modifiers.subtracting(.shift) == .command, let key = character(of: event)
        else { return super.performKeyEquivalent(with: event) }
        if let textEditor { return Self.performTextCommand(key, shift: modifiers.contains(.shift), in: textEditor) }
        switch (key, modifiers.contains(.shift)) {
        case ("c", false):
            if session.area != nil { run(.copy) }
        case ("s", false):
            if session.area != nil { run(.save) }
        case ("t", true):
            if session.area != nil { run(.copyText) }
        case ("a", false):
            guard session.tool == nil else { return true }
            session.selectWholeDisplay()
            changed()
        case ("z", false):
            apply(.undo)
        case ("z", true):
            session.redo()
            changed()
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    private func pressMarkup(at point: CGPoint, clickCount: Int) {
        guard isInsideArea(point) else { return }
        if clickCount == 2, session.editText(at: point, on: display) {
            beginTextEdit()
        } else if session.pressAnnotation(at: point, on: display) {
            beginTextEdit()
        } else {
            gesture = .markup
        }
    }

    private func run(_ intent: ScreenshotIntent) {
        endTextEdit()
        perform(intent)
    }

    private func apply(_ command: MarkupCommand) {
        switch command {
        case .choose(let tool):
            endTextEdit()
            session.choose(tool)
            NSCursor.crosshair.set()
        case .restyle(let style):
            session.restyle(style)
        case .undo:
            endTextEdit()
            session.undo()
        }
        changed()
    }

    private func beginTextEdit() {
        guard textEditor == nil, let editing = session.board.editing else { return }
        let editor = TextEditOverlay(
            text: editing.typedText ?? "", font: textFont(editing.style), color: textColor(editing),
            origin: textOrigin(editing), changed: { [weak self] in self?.typed($0) },
            finished: { [weak self] in self?.endTextEdit() })
        if chromeHost == nil {
            addSubview(editor, positioned: .below, relativeTo: loupe)
        } else {
            addSubview(editor)
        }
        textEditor = editor
        window?.makeFirstResponder(editor)
        NSCursor.iBeam.set()
    }

    private func typed(_ text: String) {
        session.updateText(text)
        changed()
    }

    func endTextEdit() {
        guard let editor = textEditor else { return }
        textEditor = nil
        editor.removeFromSuperview()
        session.endText()
        window?.makeFirstResponder(self)
        changed()
    }

    private func renderTextEditor() {
        guard let textEditor, let editing = session.board.editing else { return }
        textEditor.restyle(font: textFont(editing.style), color: textColor(editing))
        textEditor.setFrameOrigin(textOrigin(editing))
    }

    private func textFont(_ style: AnnotationStyle) -> NSFont {
        AnnotationText.font(size: Theme.Markup.textSizes[style.textSize.rawValue])
    }

    private func textColor(_ annotation: Annotation) -> NSColor {
        NSColor(AnnotationAppearance.color(annotation.style.ink))
    }

    private func textOrigin(_ annotation: Annotation) -> CGPoint {
        guard case .text(_, let origin) = annotation.shape else { return .zero }
        return CGPoint(x: origin.x / display.scale, y: origin.y / display.scale)
    }

    private func renderMarkup(in area: PixelRect?) {
        guard let area else {
            areaLayer.isHidden = true
            selectionLayer.path = nil
            return
        }
        let frame = display.points(area)
        areaLayer.isHidden = false
        areaLayer.frame = frame
        renderWindowShot(in: frame)
        let annotations = session.board.visible
        let toArea = CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
            .scaledBy(x: 1 / display.scale, y: 1 / display.scale)
        renderMosaic(annotations, in: frame)
        let metrics = session.metrics(on: display)
        let marks = annotations.filter { !$0.isMosaic }
        let visiblePixels = visibleRect.applying(CGAffineTransform(scaleX: display.scale, y: display.scale))
        let region = marks.reduce(CGRect.null) { $0.union(AnnotationGeometry.frame(of: $1, metrics: metrics)) }
            .insetBy(dx: -display.scale * 2, dy: -display.scale * 2).integral.intersection(area.cgRect)
            .intersection(visiblePixels.integral)
        marksLayer.isHidden = region.isEmpty
        marksLayer.frame = region.isEmpty ? .zero : region.applying(toArea)
        marksLayer.content = AnnotationLayer.Content(
            marks: region.isEmpty ? [] : marks, region: region, hiddenText: session.board.editing?.id)
        let focused = session.board.selected ?? session.board.editing
        let outlined = [focused, hoveredAnnotation.flatMap { $0.id == focused?.id ? nil : $0 }].compactMap { $0 }
        let toPoints = CGAffineTransform(scaleX: 1 / display.scale, y: 1 / display.scale)
        let outlines = CGMutablePath()
        for annotation in outlined {
            outlines.addRect(AnnotationGeometry.selectionFrame(of: annotation, metrics: metrics).applying(toPoints))
        }
        selectionLayer.path = outlined.isEmpty ? nil : outlines
    }

    private var hoveredAnnotation: Annotation? {
        guard session.tool != nil, gesture == nil, textEditor == nil, let pointer = session.pointer,
            pointer.display == display.id, isInsideArea(pointer.location)
        else { return nil }
        return session.annotation(at: pointer.location, on: display)
    }

    private func renderMosaic(_ annotations: [Annotation], in frame: CGRect) {
        let source = annotations.contains(where: \.isMosaic) ? session.mosaicSource(for: display) : nil
        let metrics = session.metrics(on: display)
        let visible = visibleRect
        var toMask = CGAffineTransform(translationX: -visible.minX, y: -visible.minY)
            .scaledBy(x: 1 / display.scale, y: 1 / display.scale)
        let layers = [(pixelateLayer, pixelateMask, AnnotationStyle.MosaicEffect.pixelate), (blurLayer, blurMask, .blur)]
        for (layer, mask, effect) in layers {
            guard let source, let path = AnnotationPainter.mosaicPath(annotations, effect: effect, metrics: metrics)
            else {
                layer.isHidden = true
                layer.contents = nil
                continue
            }
            layer.isHidden = false
            layer.contents = source.image(for: effect)
            layer.frame = CGRect(origin: CGPoint(x: -frame.minX, y: -frame.minY), size: bounds.size)
            mask.frame = visible
            mask.path = path.copy(using: &toMask)
        }
    }

    private func renderWindowShot(in area: CGRect) {
        guard let shot = session.windowShot, shot.display == display.id, let image = shot.image else {
            windowLayer.isHidden = true
            windowLayer.contents = nil
            return
        }
        windowLayer.contents = image
        windowLayer.frame = display.points(shot.frame).offsetBy(dx: -area.minX, dy: -area.minY)
        windowLayer.isHidden = false
    }

    private func renderLoupe() {
        guard session.showsLoupe, let pointer = session.pointer, pointer.display == display.id else {
            loupe.isHidden = true
            return
        }
        let pixel = display.pixel(pointer.location)
        let color = PixelColor(image: display.image, at: pixel)?.hex ?? ""
        let position =
            session.showsPixels
            ? "\(pixel.x), \(pixel.y)"
            : "\(Int(pointer.location.x)), \(Int(pointer.location.y))"
        loupe.show(pixel: pixel, caption: "\(position)\n\(color)")
        place(
            loupe,
            at: ChromePlacement.loupe(
                size: LoupeView.size, cursor: pointer.location, in: chromeBounds, offset: Theme.Size.loupeOffset))
        loupe.isHidden = false
    }

    private func renderChrome(around area: CGRect?) {
        guard let area, let rect = session.area?.rect else {
            pill.isHidden = true
            toolbar.isHidden = true
            optionsBar.isHidden = true
            return
        }
        let text =
            session.showsPixels
            ? "\(rect.width) × \(rect.height) px"
            : "\(Int((area.width).rounded())) × \(Int((area.height).rounded()))"
        if text != pillText {
            pillText = text
            pill.rootView = sizePill(text)
            pillSize = pill.fittingSize
        }
        let bounds = chromeBounds
        let shown = Self.anchor(area, in: visibleRect)
        place(pill, at: ChromePlacement.sizePill(size: pillSize, area: shown, in: bounds, gap: Theme.Spacing.xs))
        pill.isHidden = false
        toolbarFrame = ChromePlacement.toolbar(size: toolbarSize, area: shown, in: bounds, gap: Theme.Spacing.md)
        place(toolbar, at: toolbarFrame)
        toolbar.isHidden = session.isDragging
        renderOptionsBar()
    }

    private func renderOptionsBar() {
        guard let tool = session.tool, !toolbar.isHidden else {
            optionsBar.isHidden = true
            return
        }
        if tool != optionsTool {
            optionsTool = tool
            optionsBar.rootView = optionsBarView(for: tool)
            optionsSize = optionsBar.fittingSize
        }
        place(
            optionsBar,
            at: ChromePlacement.optionsBar(size: optionsSize, toolbar: toolbarFrame, in: chromeBounds, gap: Theme.Spacing.xs))
        optionsBar.isHidden = false
    }

    private var chromeBounds: CGRect {
        guard let chromeHost else { return visibleRect }
        return convert(chromeHost.bounds, from: chromeHost)
    }

    private func place(_ chrome: NSView, at frame: CGRect) {
        chrome.frame = chromeHost.map { $0.convert(frame, from: self) } ?? frame
    }

    private func optionsBarView(for tool: ScreenshotTool) -> ToolOptionsBar {
        ToolOptionsBar(tool: tool, session: session, metrics: chromeMetrics) { [weak self] in self?.apply($0) }
    }

    private func sizePill(_ text: String) -> SelectionSizePill {
        SelectionSizePill(metrics: metrics, size: text, showsPixels: session.showsPixels) { [weak self] in
            guard let self else { return }
            session.showsPixels.toggle()
            changed()
        }
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor(Theme.Colors.primaryAction).cgColor
            dimLayer.fillColor = NSColor(Theme.Colors.captureDim).cgColor
            borderLayer.strokeColor = accent
            handlesLayer.fillColor = accent
            handlesLayer.strokeColor = NSColor(Theme.Colors.captureHandleRim).cgColor
            selectionLayer.strokeColor = accent
        }
    }

    private func isInsideArea(_ point: CGPoint) -> Bool {
        guard let area = session.area, area.display == display.id else { return false }
        return area.rect.contains(display.pixel(point))
    }

    private func cursor(at point: CGPoint) -> NSCursor {
        let overChrome = [pill, toolbar, optionsBar].contains { chrome in
            !chrome.isHidden && convert(chrome.frame, from: chrome.superview).contains(point)
        }
        if overChrome { return .arrow }
        if textEditor != nil {
            if session.board.isMoving { return .closedHand }
            if session.gripsEditingText(at: point, on: display) { return .openHand }
        }
        if let tool = session.tool { return markupCursor(at: point, tool: tool) }
        switch session.editKind {
        case .move?: return .closedHand
        case .resize(let handle)?: return Self.resizeCursor(handle)
        case .draw?: return .crosshair
        case nil: break
        }
        guard let area = session.area, area.display == display.id else { return .crosshair }
        let pixel = display.gridPoint(point)
        let reach = Int(Theme.Size.captureHandleReach * display.scale)
        if let handle = SelectionHandle.at(pixel, of: area.rect, reach: reach) { return Self.resizeCursor(handle) }
        return area.rect.contains(pixel) ? .openHand : .crosshair
    }

    private func markupCursor(at point: CGPoint, tool: ScreenshotTool) -> NSCursor {
        guard isInsideArea(point) else { return .arrow }
        if gesture == .markup, session.board.isMoving { return .closedHand }
        guard gesture == nil, session.annotation(at: point, on: display) != nil else {
            return tool == .text ? .iBeam : .crosshair
        }
        return .openHand
    }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func character(of event: NSEvent) -> String? {
        (ASCIIKeyboardLayout.character(for: event) ?? event.charactersIgnoringModifiers)?.lowercased()
    }

    /// The panel has no Edit menu to send these, so the canvas hands them to the text view itself.
    private static func performTextCommand(_ key: String, shift: Bool, in editor: TextEditOverlay) -> Bool {
        switch (key, shift) {
        case ("z", false): editor.undoManager?.undo()
        case ("z", true): editor.undoManager?.redo()
        case ("x", false): editor.cut(nil)
        case ("c", false): editor.copy(nil)
        case ("v", false): editor.paste(nil)
        case ("a", false): editor.selectAll(nil)
        default: return false
        }
        return true
    }

    private static func direction(_ keyCode: UInt16) -> (Int, Int) {
        switch keyCode {
        case Key.left: return (-1, 0)
        case Key.right: return (1, 0)
        case Key.up: return (0, -1)
        default: return (0, 1)
        }
    }

    private static func anchor(_ area: CGRect, in visible: CGRect) -> CGRect {
        let shown = area.intersection(visible)
        guard shown.isNull else { return shown }
        let y = min(max(area.minY, visible.minY), visible.maxY)
        return CGRect(x: area.minX, y: y, width: area.width, height: 0)
    }

    private static func strip(at y: Int, of image: CGImage) -> PixelRect {
        PixelRect(x: 0, y: y, width: image.width, height: min(stripPixels, image.height - y))
    }

    private func renderImageStrips() {
        guard !imageStrips.isEmpty else { return }
        let near = visibleRect.insetBy(dx: 0, dy: -visibleRect.height)
        for (index, layer) in imageStrips.enumerated() {
            guard layer.frame.intersects(near) else {
                layer.contents = nil
                continue
            }
            guard layer.contents == nil else { continue }
            layer.contents = display.image.cropping(to: Self.strip(at: index * Self.stripPixels, of: display.image).cgRect)
        }
    }

    private static func handlesPath(_ area: CGRect, near visible: CGRect) -> CGPath {
        let path = CGMutablePath()
        let radius = Theme.Size.captureHandle / 2
        for x in [area.minX, area.midX, area.maxX] {
            for y in [area.minY, area.midY, area.maxY]
            where (x != area.midX || y != area.midY) && visible.contains(CGPoint(x: x, y: y)) {
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
        return path
    }

    private static func resizeCursor(_ handle: SelectionHandle) -> NSCursor {
        let position: NSCursor.FrameResizePosition
        switch handle {
        case .topLeft: position = .topLeft
        case .top: position = .top
        case .topRight: position = .topRight
        case .right: position = .right
        case .bottomRight: position = .bottomRight
        case .bottom: position = .bottom
        case .bottomLeft: position = .bottomLeft
        case .left: position = .left
        }
        return .frameResize(position: position, directions: .all)
    }
}
