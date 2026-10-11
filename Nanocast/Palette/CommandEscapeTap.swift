import AppKit
import Carbon.HIToolbox

private func commandEscapeTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<CommandEscapeTap>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard
        CommandEscapeTap.isChord(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags)
    else { return Unmanaged.passUnretained(event) }

    let claimed = MainActor.assumeIsolated { tap.fire() }
    return claimed ? nil : Unmanaged.passUnretained(event)
}

@MainActor
final class CommandEscapeTap {
    private let onChord: () -> Bool

    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onChord: @escaping () -> Bool) {
        self.onChord = onChord
    }

    isolated deinit {
        tearDown()
    }

    nonisolated static func isChord(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == Int64(kVK_Escape)
            && flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
                == .maskCommand
    }

    func enable() {
        guard let port = installIfNeeded() else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func disable() {
        guard let tapPort else { return }
        CGEvent.tapEnable(tap: tapPort, enable: false)
    }

    private func installIfNeeded() -> CFMachPort? {
        if let tapPort { return tapPort }
        // Head of the HID stream: anywhere later and the system hotkey has already eaten the chord.
        guard
            let port = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
                callback: commandEscapeTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        else { return nil }
        tapPort = port
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return port
    }

    private func tearDown() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
            self.tapPort = nil
        }
    }

    fileprivate func fire() -> Bool {
        onChord()
    }

    /// The system disables a tap it thinks is too slow; ours only ever compares two integers.
    fileprivate func reenable() {
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }
}
