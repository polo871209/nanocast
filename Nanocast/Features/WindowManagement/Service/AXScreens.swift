import AppKit
import ColorSync

struct AXGeometry {
    let anchorHeight: CGFloat

    @MainActor
    init(screens: [NSScreen]) {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        anchorHeight = primary?.frame.height ?? 0
    }

    func flip(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x, y: anchorHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

@MainActor
enum AXScreens {
    static func converted(
        _ screens: [NSScreen], geometry: AXGeometry
    ) -> [WindowPlacementEngine.Screen] {
        let hiddenDock = autoHiddenDockEdge()
        return screens.enumerated().map { index, screen in
            let converted = WindowPlacementEngine.Screen(
                id: displayID(screen).map(Int.init) ?? -(index + 1),
                frame: geometry.flip(screen.frame),
                visibleFrame: geometry.flip(screen.visibleFrame))
            return hiddenDock.map(converted.reclaiming) ?? converted
        }
    }

    // An auto-hidden Dock still shrinks `visibleFrame` while it is revealed or sliding away.
    private static func autoHiddenDockEdge() -> WindowPlacementEngine.DockEdge? {
        guard let dock = UserDefaults(suiteName: "com.apple.dock"), dock.bool(forKey: "autohide")
        else { return nil }
        return dock.string(forKey: "orientation").flatMap(WindowPlacementEngine.DockEdge.init)
            ?? .bottom
    }

    static func layoutScreens(geometry: AXGeometry) -> [WindowLayoutScreen] {
        let screens = NSScreen.screens
        let converted = converted(screens, geometry: geometry)
        let ordered = WindowPlacementEngine.ordered(converted)
        return ordered.compactMap { screen in
            guard let index = converted.firstIndex(where: { $0.id == screen.id }),
                let uuid = uuid(of: screens[index])
            else { return nil }
            return WindowLayoutScreen(
                display: WindowLayoutDisplay(uuid: uuid, name: screens[index].localizedName),
                screen: screen)
        }
    }

    static func uuid(of screen: NSScreen) -> String? {
        guard let id = displayID(screen),
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
            let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return string.lowercased()
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }
}
