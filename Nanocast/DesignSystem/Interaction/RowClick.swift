import SwiftUI

struct RowDragItem {
    let writer: any NSPasteboardWriting
    let image: NSImage

    static func file(_ url: URL, image: NSImage?) -> RowDragItem {
        RowDragItem(writer: url as NSURL, image: image ?? NSWorkspace.shared.icon(forFile: url.path))
    }
}

struct RowDrag {
    let item: () -> RowDragItem?
    let dropped: () -> Void
}

extension View {
    func onRowClick(
        select: @escaping () -> Void, activate: @escaping () -> Void, drag: RowDrag? = nil
    ) -> some View {
        overlay(
            RowPressCatcher(activation: .doubleClick, select: select, activate: activate, drag: drag))
    }

    @ViewBuilder
    func onRowTap(drag: RowDrag?, perform activate: @escaping () -> Void) -> some View {
        if let drag {
            overlay(RowPressCatcher(activation: .release, select: {}, activate: activate, drag: drag))
        } else {
            onTapGesture(perform: activate)
        }
    }
}

/// AppKit, not `onDrag`: only an `NSDraggingSource` can force `.copy` over a same-volume move.
private struct RowPressCatcher: NSViewRepresentable {
    let activation: RowPressView.Activation
    let select: () -> Void
    let activate: () -> Void
    let drag: RowDrag?

    func makeNSView(context: Context) -> RowPressView { RowPressView() }

    func updateNSView(_ view: RowPressView, context: Context) {
        view.activation = activation
        view.select = select
        view.activate = activate
        view.drag = drag
    }
}

/// Owns the whole left press, because the hosting view otherwise eats the click first.
private final class RowPressView: NSView, NSDraggingSource {
    enum Activation {
        case doubleClick
        case release
    }

    private static let dragSlop: CGFloat = 4

    var activation = Activation.doubleClick
    var select: () -> Void = {}
    var activate: () -> Void = {}
    var drag: RowDrag?

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        select()
        if activation == .doubleClick {
            guard event.clickCount < 2 else {
                activate()
                return
            }
            guard drag != nil else { return }
        }
        guard pressBecomesDrag() else {
            if activation == .release { activate() }
            return
        }
        guard let item = drag?.item() else { return }
        beginDrag(item, with: event)
    }

    private func pressBecomesDrag() -> Bool {
        guard let window else { return false }
        let start = NSEvent.mouseLocation
        var passedSlop = false
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            guard let tracked, tracked.type != .leftMouseUp else {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            guard hypot(mouse.x - start.x, mouse.y - start.y) > Self.dragSlop else { return }
            passedSlop = true
            stop.pointee = true
        }
        return passedSlop
    }

    private func beginDrag(_ item: RowDragItem, with event: NSEvent) {
        let image = item.image
        let dragging = NSDraggingItem(pasteboardWriter: item.writer)
        let origin = convert(event.locationInWindow, from: nil)
        dragging.setDraggingFrame(
            NSRect(
                x: origin.x - image.size.width / 2, y: origin.y - image.size.height / 2,
                width: image.size.width, height: image.size.height),
            contents: image)
        let session = beginDraggingSession(with: [dragging], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        guard operation != [] else { return }
        drag?.dropped()
    }
}
