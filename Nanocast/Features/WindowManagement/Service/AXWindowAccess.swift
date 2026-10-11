// Portions adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
// `@preconcurrency` downgrades AX diagnostics: `kAX…` are mutable C globals, but constant.
@preconcurrency import ApplicationServices

@MainActor
enum AXWindowAccess {
    static let messagingTimeout: Float = 1
    static let clampTolerance: CGFloat = 2

    static let fullScreenAttribute = "AXFullScreen" as CFString
    static let fullScreenButtonAttribute = "AXFullScreenButton" as CFString

    static func application(for pid: pid_t, timeout: Float = messagingTimeout) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        return application
    }

    static func targetWindow(in application: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = element(application, attribute), isEligible(window) { return window }
        }
        return windows(in: application).first(where: isEligible)
    }

    static func windows(in application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
                == .success,
            let windows = value as? [AXUIElement]
        else { return [] }
        return windows
    }

    static func isEligible(_ window: AXUIElement) -> Bool {
        guard string(window, kAXRoleAttribute) == (kAXWindowRole as String) else { return false }
        if bool(window, kAXMinimizedAttribute) == true { return false }
        return frame(of: window) != nil
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, fullScreenAttribute, &value) == .success
        else { return false }
        return (value as? Bool) ?? false
    }

    static func unminimize(_ window: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            == .success
    }

    static func minimize(_ window: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            == .success
    }

    static func focus(
        _ window: AXUIElement, in application: AXUIElement, of app: NSRunningApplication
    ) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // Belt and braces with `activate()`: an agent-policy app's request can be ignored.
        AXUIElementSetAttributeValue(
            application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    static func raise(_ window: AXUIElement, in application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    static func setHidden(_ hidden: Bool, application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, kAXHiddenAttribute as CFString, hidden ? kCFBooleanTrue : kCFBooleanFalse)
    }

    /// Web-based apps list no windows until this is on, and draw focus rings while it stays on.
    static func setManualAccessibility(_ enabled: Bool, application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, "AXManualAccessibility" as CFString,
            enabled ? kCFBooleanTrue : kCFBooleanFalse)
    }

    static func windowID(of window: AXUIElement) -> UInt32? {
        guard let copyWindowID else { return nil }
        var id: CGWindowID = 0
        return copyWindowID(window, &id) == .success && id != 0 ? id : nil
    }

    private typealias CopyWindowID =
        @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// Private, so resolved at run time: a macOS without it degrades to titles, never a crash.
    private static let copyWindowID: CopyWindowID? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: CopyWindowID.self)
    }()

    static func write(
        _ target: CGRect, anchor: WindowPlacementEngine.Anchor, to window: AXUIElement,
        current: CGRect, canResize: Bool, canvas: CGRect?
    ) -> CGRect? {
        guard canResize else {
            var slot = anchor.place(current.size, in: target)
            if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
            guard setPosition(WindowPlacementEngine.rounded(slot).origin, on: window) else {
                return nil
            }
            return frame(of: window) ?? current
        }

        _ = setSize(target.size, on: window)
        guard setPosition(target.origin, on: window) else {
            _ = setSize(current.size, on: window)
            return nil
        }
        _ = setSize(target.size, on: window)

        guard var actual = frame(of: window) else { return target }

        if abs(actual.minX - target.minX) > clampTolerance
            || abs(actual.minY - target.minY) > clampTolerance
        {
            _ = setPosition(target.origin, on: window)
            actual = frame(of: window) ?? actual
        }

        if actual.width > target.width + clampTolerance
            || actual.height > target.height + clampTolerance
        {
            var slot = anchor.place(actual.size, in: target)
            if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
            _ = setPosition(WindowPlacementEngine.rounded(slot).origin, on: window)
            actual = frame(of: window) ?? actual
        }
        return actual
    }

    static func suppressEnhancedUserInterface(on application: AXUIElement) -> () -> Void {
        let attribute = "AXEnhancedUserInterface" as CFString
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return {} }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute, &value) == .success,
            (value as? Bool) == true
        else { return {} }
        AXUIElementSetAttributeValue(application, attribute, kCFBooleanFalse)
        return { AXUIElementSetAttributeValue(application, attribute, kCFBooleanTrue) }
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute),
            let size = size(window, kAXSizeAttribute)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func setPosition(_ origin: CGPoint, on window: AXUIElement) -> Bool {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            == .success
    }

    static func setSize(_ size: CGSize, on window: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute, type: .cgPoint) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute, type: .cgSize) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    static func axValue(
        _ element: AXUIElement, _ attribute: String, type: AXValueType
    ) -> AXValue? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    static func isSettable(_ attribute: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }
}
