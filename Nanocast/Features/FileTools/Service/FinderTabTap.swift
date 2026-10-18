import AppKit
import ApplicationServices

private func finderTabTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let relay = Unmanaged<FinderTabTap.Relay>.fromOpaque(userInfo).takeUnretainedValue()
    guard type == .keyDown else {
        relay.tapDisabled()
        return Unmanaged.passUnretained(event)
    }
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags.rawValue
    guard FinderTabPolicy.isCandidate(keyCode: keyCode, flags: flags) else { return Unmanaged.passUnretained(event) }
    let focus = relay.focus()
    guard FinderTabPolicy.opensFileTools(keyCode: keyCode, flags: flags, focus: focus) else {
        return Unmanaged.passUnretained(event)
    }
    relay.open()
    return nil
}

@MainActor
final class FinderTabTap {
    fileprivate enum Signal: Sendable {
        case open
        case disabled
    }

    fileprivate final class Relay: Sendable {
        private static let messagingTimeout: Float = 0.1

        private let pid: pid_t
        private let deliver: @MainActor @Sendable (Signal) -> Void

        init(pid: pid_t, deliver: @escaping @MainActor @Sendable (Signal) -> Void) {
            self.pid = pid
            self.deliver = deliver
        }

        func focus() -> FinderFocus? {
            let finder = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(finder, Self.messagingTimeout)
            guard let focused: AXUIElement = value(of: kAXFocusedUIElementAttribute, on: finder),
                let role: String = value(of: kAXRoleAttribute, on: focused)
            else { return nil }
            let selected: [AXUIElement]? =
                value(of: kAXSelectedChildrenAttribute, on: focused) ?? value(of: kAXSelectedRowsAttribute, on: focused)
            return FinderFocus(
                role: role, subrole: value(of: kAXSubroleAttribute, on: focused), selectionCount: selected?.count)
        }

        func open() { send(.open) }

        func tapDisabled() { send(.disabled) }

        private func value<Value>(of attribute: String, on element: AXUIElement) -> Value? {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
            return raw as? Value
        }

        private func send(_ signal: Signal) {
            Task { @MainActor [deliver] in deliver(signal) }
        }
    }

    private let onOpen: () -> Void
    private var relay: Relay?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var pid: pid_t?

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
    }

    isolated deinit {
        uninstall()
    }

    var isInstalled: Bool { port != nil }

    /// Returns false while Accessibility is missing or Finder is not running.
    @discardableResult
    func install() -> Bool {
        let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: FinderSelectionReader.bundleIdentifier
        ).first { !$0.isTerminated }
        guard let finder else { return false }
        if isInstalled, pid == finder.processIdentifier { return true }
        removeTap()
        let relay = Relay(pid: finder.processIdentifier) { [weak self] in self?.receive($0) }
        guard
            let port = CGEvent.tapCreateForPid(
                pid: finder.processIdentifier, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: 1 << CGEventType.keyDown.rawValue, callback: finderTabTapCallback,
                userInfo: Unmanaged.passUnretained(relay).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.relay = relay
        self.port = port
        self.source = source
        pid = finder.processIdentifier
        return true
    }

    func uninstall() {
        removeTap()
    }

    private func removeTap() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        source = nil
        port = nil
        relay = nil
        pid = nil
    }

    private func receive(_ signal: Signal) {
        switch signal {
        case .open:
            onOpen()
        case .disabled:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        }
    }
}
