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
        var entries: [WindowSwitchEntry]
        var elements: [Int: Element]
    }

    static func snapshot(ranks: [pid_t: Int]) -> Snapshot {
        var entries: [WindowSwitchEntry] = []
        var elements: [Int: Element] = [:]

        for app in WindowInventory.candidates() {
            guard let bundleID = app.bundleIdentifier else { continue }
            let pid = app.processIdentifier
            let application = AXWindowAccess.application(for: pid, timeout: sweepTimeout)
            let iconURL = app.bundleURL
            let iconStamp = iconURL.map(FileIconStamp.value(for:)) ?? 0
            for window in AXWindowAccess.windows(in: application) {
                AXUIElementSetMessagingTimeout(window, sweepTimeout)
                let minimized = AXWindowAccess.bool(window, kAXMinimizedAttribute) == true
                guard isSwitchable(window, minimized: minimized) else { continue }
                let handle = entries.count
                entries.append(
                    WindowSwitchEntry(
                        handle: handle, appName: app.localizedName ?? bundleID,
                        bundleID: bundleID, iconURL: iconURL, iconStamp: iconStamp,
                        title: AXWindowAccess.string(window, kAXTitleAttribute) ?? "",
                        isMinimized: minimized, appRank: ranks[pid] ?? .max))
                elements[handle] = Element(app: app, application: application, window: window)
            }
        }
        return Snapshot(entries: entries, elements: elements)
    }

    private static func isSwitchable(_ window: AXUIElement, minimized: Bool) -> Bool {
        WindowSwitchPolicy.isSwitchable(
            isStandardWindow: AXWindowAccess.string(window, kAXSubroleAttribute)
                == (kAXStandardWindowSubrole as String),
            isMinimized: minimized,
            canMinimize: AXWindowAccess.element(window, kAXMinimizeButtonAttribute) != nil)
    }
}
