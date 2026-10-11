import AppKit
@preconcurrency import ApplicationServices

@MainActor
enum WindowInventory {
    private static let sweepTimeout: Float = 0.2

    struct Element {
        let bundleID: String
        let app: NSRunningApplication
        let application: AXUIElement
        let window: AXUIElement
    }

    struct Snapshot {
        var screens: [WindowLayoutScreen]
        var windows: [WindowLayoutWindow]
        var elements: [Int: Element]
    }

    static func snapshot(positionableOnly: Bool = false) -> Snapshot {
        let geometry = AXGeometry(screens: NSScreen.screens)
        var windows: [WindowLayoutWindow] = []
        var elements: [Int: Element] = [:]

        for app in candidates() {
            guard let bundleID = app.bundleIdentifier else { continue }
            let application = AXWindowAccess.application(
                for: app.processIdentifier, timeout: sweepTimeout)
            for window in AXWindowAccess.windows(in: application) {
                AXUIElementSetMessagingTimeout(window, sweepTimeout)
                guard let frame = eligibleFrame(window, positionableOnly: positionableOnly)
                else { continue }
                let handle = windows.count
                windows.append(
                    WindowLayoutWindow(
                        handle: handle, bundleID: bundleID, frame: frame,
                        title: AXWindowAccess.string(window, kAXTitleAttribute) ?? ""))
                elements[handle] = Element(
                    bundleID: bundleID, app: app, application: application, window: window)
            }
        }
        return Snapshot(
            screens: AXScreens.layoutScreens(geometry: geometry), windows: windows,
            elements: elements)
    }

    static func unclaimedWindows(
        of application: AXUIElement, excluding claimed: some Collection<AXUIElement>
    ) -> [AXUIElement] {
        AXWindowAccess.windows(in: application).filter { window in
            AXUIElementSetMessagingTimeout(window, sweepTimeout)
            guard eligibleFrame(window, positionableOnly: true) != nil else { return false }
            return !claimed.contains { CFEqual($0, window) }
        }
    }

    static func candidates() -> [NSRunningApplication] {
        let ownPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
                && $0.processIdentifier != ownPID
        }
    }

    static func application(for bundleID: String) -> (AXUIElement, NSRunningApplication)? {
        guard
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { !$0.isTerminated })
        else { return nil }
        return (AXWindowAccess.application(for: app.processIdentifier), app)
    }

    private static func eligibleFrame(
        _ window: AXUIElement, positionableOnly: Bool
    ) -> CGRect? {
        guard
            AXWindowAccess.string(window, kAXSubroleAttribute)
                == (kAXStandardWindowSubrole as String)
        else { return nil }
        guard AXWindowAccess.bool(window, kAXMinimizedAttribute) != true,
            !AXWindowAccess.isFullScreen(window), let frame = AXWindowAccess.frame(of: window),
            frame.width > 0, frame.height > 0
        else { return nil }
        guard !positionableOnly || AXWindowAccess.isSettable(kAXPositionAttribute, on: window)
        else { return nil }
        return frame
    }
}
