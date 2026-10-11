import AppKit
@preconcurrency import ApplicationServices

@MainActor
enum WindowSwitchSweep {
    private static let sweepTimeout: Float = 0.2

    struct Element {
        enum Target {
            case live(AXUIElement)
            case unresolved(windowID: UInt32)
        }

        let app: NSRunningApplication
        let application: AXUIElement
        let target: Target

        @MainActor func resolveWindow() -> AXUIElement? {
            switch target {
            case .live(let window):
                return window
            case .unresolved(let windowID):
                let application = AXWindowAccess.application(for: app.processIdentifier)
                return AXWindowAccess.windows(in: application).first {
                    AXWindowAccess.windowID(of: $0) == windowID
                }
            }
        }
    }

    struct Snapshot {
        var entries: [WindowSwitchEntry] = []
        var elements: [Int: Element] = [:]
    }

    private enum Verdict {
        case switchable
        case skipped
        case unknown
    }

    static func snapshot(excluding excludedBundleIDs: Set<String>) -> Snapshot {
        var snapshot = Snapshot()
        let onScreen = onScreenWindows()
        for app in WindowInventory.candidates() where !app.isHidden {
            guard let bundleID = app.bundleIdentifier, !excludedBundleIDs.contains(bundleID)
            else { continue }
            let application = AXWindowAccess.application(
                for: app.processIdentifier, timeout: sweepTimeout)
            let iconURL = app.bundleURL
            let iconStamp = iconURL.map(FileIconStamp.value(for:)) ?? 0
            func append(windowID: UInt32?, title: String, target: Element.Target) {
                let handle = snapshot.entries.count
                snapshot.entries.append(
                    WindowSwitchEntry(
                        handle: handle, windowID: windowID, pid: app.processIdentifier,
                        appName: app.localizedName ?? bundleID, iconURL: iconURL,
                        iconStamp: iconStamp, title: title))
                snapshot.elements[handle] = Element(
                    app: app, application: application, target: target)
            }

            var reported = Set<UInt32>()
            var reportsWindowIDs = true
            for window in AXWindowAccess.windows(in: application) {
                AXUIElementSetMessagingTimeout(window, sweepTimeout)
                let windowID = AXWindowAccess.windowID(of: window)
                let verdict = verdict(for: window)
                if verdict != .unknown {
                    if let windowID { reported.insert(windowID) } else { reportsWindowIDs = false }
                }
                guard verdict == .switchable else { continue }
                append(
                    windowID: windowID,
                    title: AXWindowAccess.string(window, kAXTitleAttribute) ?? "",
                    target: .live(window))
            }
            guard reportsWindowIDs else { continue }
            for window in WindowSwitchFallbackPolicy.unlisted(
                onScreen, of: app.processIdentifier, reported: reported)
            {
                append(
                    windowID: window.id, title: window.title,
                    target: .unresolved(windowID: window.id))
            }
        }
        return snapshot
    }

    private static func verdict(for window: AXUIElement) -> Verdict {
        guard let subrole = AXWindowAccess.string(window, kAXSubroleAttribute) else {
            return .unknown
        }
        guard subrole == (kAXStandardWindowSubrole as String),
            AXWindowAccess.bool(window, kAXMinimizedAttribute) != true
        else { return .skipped }
        return .switchable
    }

    private static func onScreenWindows() -> [ServerWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return listing.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? UInt32,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                let layer = info[kCGWindowLayer as String] as? Int,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return ServerWindow(
                id: id, pid: pid, layer: layer,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 1, size: frame.size,
                title: info[kCGWindowName as String] as? String ?? "")
        }
    }
}
