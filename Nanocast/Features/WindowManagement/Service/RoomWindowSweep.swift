// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
@preconcurrency import ApplicationServices

@MainActor
enum RoomWindowSweep {
    private static let sweepTimeout: Float = 0.2
    private static let smallest = CGSize(width: 100, height: 60)
    /// Layer 0 is the normal window band; above it sit the menu bar, the Dock and overlays.
    private static let normalLayer = 0

    struct Snapshot {
        var screens: [WindowLayoutScreen]
        var windows: [RoomLiveWindow]
        var elements: [Int: WindowInventory.Element]

        func window(_ handle: Int) -> RoomLiveWindow? {
            windows.indices.contains(handle) ? windows[handle] : nil
        }

        func screen(uuid: String?) -> WindowLayoutScreen? {
            let uuid = uuid?.lowercased()
            return screens.first { $0.display.uuid == uuid } ?? screens.first
        }
    }

    static func snapshot() -> Snapshot {
        let geometry = AXGeometry(screens: NSScreen.screens)
        let ranks = frontRanks()
        var windows: [RoomLiveWindow] = []
        var elements: [Int: WindowInventory.Element] = [:]
        for app in WindowInventory.candidates() {
            guard let bundleID = app.bundleIdentifier else { continue }
            let application = AXWindowAccess.application(
                for: app.processIdentifier, timeout: sweepTimeout)
            for window in reportedWindows(of: application, app: app) {
                AXUIElementSetMessagingTimeout(window, sweepTimeout)
                let minimized = AXWindowAccess.bool(window, kAXMinimizedAttribute) == true
                guard isRoomWindow(window, of: app, minimized: minimized),
                    let frame = AXWindowAccess.frame(of: window),
                    frame.width >= smallest.width, frame.height >= smallest.height
                else { continue }
                let handle = windows.count
                let windowID = AXWindowAccess.windowID(of: window)
                windows.append(
                    RoomLiveWindow(
                        handle: handle, bundleID: bundleID, appName: app.localizedName ?? bundleID,
                        title: AXWindowAccess.string(window, kAXTitleAttribute) ?? "",
                        windowID: windowID, frame: frame, isMinimized: minimized,
                        isAppHidden: app.isHidden, frontRank: windowID.flatMap { ranks[$0] } ?? .max,
                        appURL: app.bundleURL))
                elements[handle] = WindowInventory.Element(
                    bundleID: bundleID, app: app, application: application, window: window)
            }
        }
        return Snapshot(
            screens: AXScreens.layoutScreens(geometry: geometry), windows: windows,
            elements: elements)
    }

    /// A web-based app can list no windows until asked through accessibility; ask, then stop.
    private static func reportedWindows(
        of application: AXUIElement, app: NSRunningApplication
    ) -> [AXUIElement] {
        let windows = AXWindowAccess.windows(in: application)
        guard windows.isEmpty, !app.isHidden else { return windows }
        AXWindowAccess.setManualAccessibility(true, application: application)
        defer { AXWindowAccess.setManualAccessibility(false, application: application) }
        return AXWindowAccess.windows(in: application)
    }

    /// A hidden or minimized app's windows read as dialogs for a while; a real one can minimize.
    private static func isRoomWindow(
        _ window: AXUIElement, of app: NSRunningApplication, minimized: Bool
    ) -> Bool {
        guard !AXWindowAccess.isFullScreen(window) else { return false }
        let subrole = AXWindowAccess.string(window, kAXSubroleAttribute)
        if subrole == (kAXStandardWindowSubrole as String) { return true }
        guard subrole == (kAXDialogSubrole as String) else { return false }
        return app.isHidden || minimized
            || AXWindowAccess.element(window, kAXMinimizeButtonAttribute) != nil
    }

    /// Front-to-back by window number. Titles are never read, so no Screen Recording grant.
    private static func frontRanks() -> [UInt32: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var ranks: [UInt32: Int] = [:]
        for window in listing where window[kCGWindowLayer as String] as? Int == normalLayer {
            guard let number = window[kCGWindowNumber as String] as? UInt32 else { continue }
            ranks[number] = ranks.count
        }
        return ranks
    }
}
