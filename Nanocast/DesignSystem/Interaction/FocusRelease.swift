import AppKit
import SwiftUI

private struct FocusReleaseOnOutsideClick: ViewModifier {
    @State private var monitor: Any?
    @State private var host = HostWindowBox()

    func body(content: Content) -> some View {
        content
            .background(HostWindowReader { host.window = $0 })
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
                    release(on: event)
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private func release(on event: NSEvent) {
        guard let window = event.window, window === host.window,
            let editor = window.firstResponder as? NSTextView, editor.isFieldEditor
        else { return }
        let hit = window.contentView?.hitTest(event.locationInWindow)
        guard let hit, !hit.isDescendant(of: editor), !(hit is NSTextView) else { return }
        window.makeFirstResponder(nil)
    }
}

private final class HostWindowBox {
    weak var window: NSWindow?
}

private struct HostWindowReader: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView { HostWindowReaderView(onResolve: onResolve) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class HostWindowReaderView: NSView {
    private let onResolve: (NSWindow?) -> Void

    init(onResolve: @escaping (NSWindow?) -> Void) {
        self.onResolve = onResolve
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onResolve(window)
    }
}

extension View {
    func releasesFocusOnOutsideClick() -> some View {
        modifier(FocusReleaseOnOutsideClick())
    }
}
