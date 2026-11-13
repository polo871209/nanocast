import AppKit
import Synchronization

private func windowSwitchTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let relay = Unmanaged<WindowSwitchTap.Relay>.fromOpaque(userInfo).takeUnretainedValue()
    let input: WindowSwitchChord.Input
    switch type {
    case .keyDown:
        input = .keyDown(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags.rawValue)
    case .keyUp:
        input = .keyUp
    case .flagsChanged:
        input = .flagsChanged(flags: event.flags.rawValue)
    default:
        relay.tapDisabled()
        return Unmanaged.passUnretained(event)
    }
    return relay.handle(input) ? nil : Unmanaged.passUnretained(event)
}

@MainActor
final class WindowSwitchTap {
    fileprivate enum Signal: Sendable {
        case action(WindowSwitchChord.Action)
        case disabled
    }

    /// The C callback runs outside actor isolation, so the chord state sits behind a lock.
    fileprivate final class Relay: Sendable {
        private let chord: Mutex<WindowSwitchChord>
        private let deliver: @MainActor @Sendable (Signal) -> Void

        init(
            trigger: WindowSwitchChord.Trigger?,
            deliver: @escaping @MainActor @Sendable (Signal) -> Void
        ) {
            chord = Mutex(WindowSwitchChord(trigger: trigger))
            self.deliver = deliver
        }

        func setTrigger(_ trigger: WindowSwitchChord.Trigger?) {
            chord.withLock { $0.trigger = trigger }
        }

        func handle(_ input: WindowSwitchChord.Input) -> Bool {
            let outcome = chord.withLock { $0.handle(input) }
            if let action = outcome.action { send(.action(action)) }
            return outcome.swallows
        }

        func tapDisabled() {
            chord.withLock { $0.end() }
            send(.disabled)
        }

        func end() {
            chord.withLock { $0.end() }
        }

        private func send(_ signal: Signal) {
            Task { @MainActor [deliver] in deliver(signal) }
        }
    }

    private let onAction: (WindowSwitchChord.Action) -> Void
    private var relay: Relay?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var trigger: WindowSwitchChord.Trigger? {
        didSet { relay?.setTrigger(trigger) }
    }

    init(onAction: @escaping (WindowSwitchChord.Action) -> Void) {
        self.onAction = onAction
    }

    isolated deinit {
        uninstall()
    }

    var isInstalled: Bool { port != nil }

    /// Returns false while Accessibility is missing, since a modifying tap needs it.
    @discardableResult
    func install() -> Bool {
        if isInstalled { return true }
        let relay = Relay(trigger: trigger) { [weak self] in self?.receive($0) }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        // Head of the HID stream: anywhere later and the Dock has already taken ⌘Tab.
        guard
            let port = CGEvent.tapCreate(
                tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: windowSwitchTapCallback,
                userInfo: Unmanaged.passUnretained(relay).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.relay = relay
        self.port = port
        self.source = source
        return true
    }

    func uninstall() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        source = nil
        port = nil
        relay = nil
    }

    func endSwitching() {
        relay?.end()
    }

    private func receive(_ signal: Signal) {
        switch signal {
        case .action(let action):
            onAction(action)
        case .disabled:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        }
    }
}
