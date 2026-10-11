import AppKit
@preconcurrency import ApplicationServices

@MainActor
enum WindowSwitchSweep {
    private static let sweepTimeout: Float = 0.2

    struct Element {
        let app: NSRunningApplication
        let application: AXUIElement
        let window: AXUIElement
    }

    struct Snapshot {
        var entries: [WindowSwitchEntry] = []
        var elements: [Int: Element] = [:]
    }

    static func snapshot(excluding excludedBundleIDs: Set<String>) -> Snapshot {
        var snapshot = Snapshot()
        for app in WindowInventory.candidates() where !app.isHidden {
            guard let bundleID = app.bundleIdentifier, !excludedBundleIDs.contains(bundleID)
            else { continue }
            let application = AXWindowAccess.application(
                for: app.processIdentifier, timeout: sweepTimeout)
            let iconURL = app.bundleURL
            let iconStamp = iconURL.map(FileIconStamp.value(for:)) ?? 0
            for window in AXWindowAccess.windows(in: application) {
                AXUIElementSetMessagingTimeout(window, sweepTimeout)
                guard isSwitchable(window) else { continue }
                let handle = snapshot.entries.count
                snapshot.entries.append(
                    WindowSwitchEntry(
                        handle: handle, windowID: AXWindowAccess.windowID(of: window),
                        pid: app.processIdentifier, appName: app.localizedName ?? bundleID,
                        iconURL: iconURL, iconStamp: iconStamp,
                        title: AXWindowAccess.string(window, kAXTitleAttribute) ?? ""))
                snapshot.elements[handle] = Element(
                    app: app, application: application, window: window)
            }
        }
        return snapshot
    }

    private static func isSwitchable(_ window: AXUIElement) -> Bool {
        AXWindowAccess.string(window, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String)
            && AXWindowAccess.bool(window, kAXMinimizedAttribute) != true
    }
}
