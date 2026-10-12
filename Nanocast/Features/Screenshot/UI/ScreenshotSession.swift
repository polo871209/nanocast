import CoreGraphics
import Observation

@MainActor
@Observable
final class ScreenshotSession {
    struct Pointer: Equatable {
        let display: UInt32
        let location: CGPoint
    }

    private(set) var displays: [CapturedDisplay] = []
    private(set) var area: DisplayArea?
    private(set) var hover: DisplayArea?
    private(set) var pointer: Pointer?
    private(set) var isDragging = false
    var showsPixels = false
    private(set) var tool: ScreenshotTool?
    private(set) var style = AnnotationStyle()
    private(set) var board = AnnotationBoard() {
        didSet {
            if canUndo != board.canUndo { canUndo = board.canUndo }
            if isMarked == board.isEmpty { isMarked = !board.isEmpty }
        }
    }
    private(set) var canUndo = false
    private(set) var isMarked = false
    private(set) var windowShot: WindowShot?

    @ObservationIgnored private var edit: SelectionEdit?
    @ObservationIgnored private var editDisplay: UInt32?
    @ObservationIgnored private var mosaics: [UInt32: MosaicSource] = [:]
    let isLongImage: Bool
    @ObservationIgnored private let windows: [ScreenWindow]
    @ObservationIgnored private let lastArea: DisplayArea?

    init(windows: [ScreenWindow], lastArea: DisplayArea?) {
        self.windows = windows
        self.lastArea = lastArea
        isLongImage = false
    }

    init(longImage display: CapturedDisplay) {
        windows = []
        lastArea = nil
        isLongImage = true
        displays = [display]
        area = DisplayArea(display: display.id, rect: display.bounds)
    }

    var editKind: SelectionEdit.Kind? { edit?.kind }

    var showsLoupe: Bool {
        guard tool == nil else { return false }
        guard let edit else { return area == nil }
        return edit.kind != .move
    }

    func colorUnderPointer() -> PixelColor? {
        guard let pointer, let display = display(pointer.display) else { return nil }
        return PixelColor(image: display.image, at: display.pixel(pointer.location))
    }

    func add(_ display: CapturedDisplay) {
        displays.append(display)
    }

    func display(_ id: UInt32) -> CapturedDisplay? {
        displays.first { $0.id == id }
    }

    func metrics(on display: CapturedDisplay) -> AnnotationMetrics {
        AnnotationAppearance.metrics(scale: display.scale)
    }

    func mosaicSource(for display: CapturedDisplay) -> MosaicSource? {
        if let source = mosaics[display.id] { return source }
        let metrics = metrics(on: display)
        let shot = windowShot?.display == display.id ? windowShot : nil
        let source = MosaicSource(
            screen: display.image, window: shot, block: metrics.mosaicBlock, blurBlock: metrics.blurBlock)
        mosaics[display.id] = source
        return source
    }

    func movePointer(to location: CGPoint, on id: UInt32) {
        pointer = Pointer(display: id, location: location)
        guard area == nil, edit == nil, let display = display(id) else { return }
        let target = DisplayArea(display: id, rect: snap(at: display.pixel(location), on: display).area)
        if hover != target { hover = target }
    }

    func press(at location: CGPoint, on id: UInt32, reach: CGFloat, slop: CGFloat) {
        guard let display = display(id) else { return }
        pointer = Pointer(display: id, location: location)
        let edit = SelectionEdit(
            pressAt: display.gridPoint(location), area: area?.display == id ? area?.rect : nil,
            bounds: display.bounds, reach: Int(reach * display.scale), slop: Int(slop * display.scale))
        guard edit.kind != .draw || board.isEmpty else { return }
        self.edit = edit
        editDisplay = id
    }

    func drag(to location: CGPoint, square: Bool, panning: Bool) {
        guard var edit, let id = editDisplay, let display = display(id) else { return }
        edit.drag(to: display.gridPoint(location), square: square, panning: panning)
        self.edit = edit
        pointer = Pointer(display: id, location: location)
        guard edit.hasMoved else { return }
        isDragging = true
        hover = nil
        if edit.kind == .draw {
            board = AnnotationBoard()
            dropWindowShot()
        }
        area = DisplayArea(display: id, rect: edit.area)
    }

    func release() -> Bool {
        defer {
            edit = nil
            editDisplay = nil
            isDragging = false
            hover = nil
        }
        guard let edit, let id = editDisplay, let display = display(id) else { return false }
        if edit.kind == .draw, edit.hasMoved, edit.area.isEmpty {
            area = nil
        } else if edit.kind == .draw, !edit.hasMoved, area == nil, let location = pointer?.location {
            let target = snap(at: display.pixel(location), on: display)
            area = DisplayArea(display: id, rect: target.area)
            if let window = target.window {
                windowShot = WindowShot(windowID: window.id, display: id, frame: window.frame)
                return true
            }
        }
        return false
    }

    func selectWholeDisplay() {
        guard edit == nil, let id = area?.display ?? pointer?.display ?? displays.first?.id, let display = display(id)
        else { return }
        dropWindowShot()
        area = DisplayArea(display: id, rect: display.bounds)
        hover = nil
    }

    func restoreLastArea() -> Bool {
        guard edit == nil, area == nil, let lastArea, let display = display(lastArea.display),
            display.bounds.contains(lastArea.rect)
        else { return false }
        area = lastArea
        hover = nil
        return true
    }

    func nudge(dx: Int, dy: Int) {
        guard edit == nil, var area, let display = display(area.display) else { return }
        area.rect = SelectionEdit.moved(area.rect, dx: dx, dy: dy, within: display.bounds)
        self.area = area
    }

    func grow(dx: Int, dy: Int) {
        guard edit == nil, var area, let display = display(area.display) else { return }
        area.rect = SelectionEdit.grown(area.rect, dx: dx, dy: dy, within: display.bounds)
        self.area = area
    }

    @discardableResult
    func clearArea() -> Bool {
        guard edit == nil, board.isEmpty else { return false }
        area = nil
        tool = nil
        board = AnnotationBoard()
        dropWindowShot()
        if let pointer { movePointer(to: pointer.location, on: pointer.display) }
        return true
    }

    func setWindowImage(_ image: CGImage?, for windowID: UInt32) {
        guard var shot = windowShot, shot.windowID == windowID else { return }
        guard let image else { return dropWindowShot() }
        shot.image = image
        windowShot = shot
        mosaics[shot.display] = nil
    }

    func choose(_ tool: ScreenshotTool?) {
        self.tool = self.tool == tool ? nil : tool
        board.select(nil)
    }

    func restyle(_ style: AnnotationStyle) {
        self.style = style
        if board.editing != nil {
            board.restyleEditing(style)
        } else {
            board.restyleSelected(style)
        }
    }

    func annotation(at location: CGPoint, on display: CapturedDisplay) -> Annotation? {
        board.annotation(at: pixels(location, on: display), metrics: metrics(on: display))
    }

    func editText(at location: CGPoint, on display: CapturedDisplay) -> Bool {
        let began = board.editText(at: pixels(location, on: display), metrics: metrics(on: display))
        if let editing = board.editing { style = editing.style }
        return began
    }

    func pressAnnotation(at location: CGPoint, on display: CapturedDisplay) -> Bool {
        guard let tool else { return false }
        let began = board.press(
            at: pixels(location, on: display), tool: tool, style: style, metrics: metrics(on: display))
        if let selected = board.selected { style = selected.style }
        if let editing = board.editing { style = editing.style }
        return began
    }

    func gripsEditingText(at location: CGPoint, on display: CapturedDisplay) -> Bool {
        board.gripsEditing(at: pixels(location, on: display), metrics: metrics(on: display))
    }

    func grabEditingText(at location: CGPoint, on display: CapturedDisplay) -> Bool {
        board.grabEditing(at: pixels(location, on: display), metrics: metrics(on: display))
    }

    func dragAnnotation(to location: CGPoint, on display: CapturedDisplay, constrained: Bool) {
        board.drag(to: pixels(location, on: display), constrained: constrained, metrics: metrics(on: display))
    }

    func releaseAnnotation() {
        board.release()
        if let editing = board.editing { style = editing.style }
    }

    func updateText(_ text: String) {
        board.updateEditing(text)
    }

    func endText() {
        board.endEditing()
    }

    func deleteSelectedAnnotation() {
        board.deleteSelected()
    }

    func undo() {
        board.undo()
    }

    func redo() {
        board.redo()
    }

    private func pixels(_ location: CGPoint, on display: CapturedDisplay) -> CGPoint {
        CGPoint(x: location.x * display.scale, y: location.y * display.scale)
    }

    private func dropWindowShot() {
        guard let shot = windowShot else { return }
        windowShot = nil
        mosaics[shot.display] = nil
    }

    private func snap(at point: PixelPoint, on display: CapturedDisplay) -> WindowSnapPolicy.Target {
        WindowSnapPolicy.target(
            at: display.quartzPoint(point), windows: windows, display: display.quartzFrame, scale: display.scale)
    }
}
