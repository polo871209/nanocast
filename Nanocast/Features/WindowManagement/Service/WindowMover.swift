import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class WindowMover {
    private struct ExternalKey: Hashable {
        let pid: pid_t
        let element: AXUIElement

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(pid)
            hasher.combine(CFHash(element))
        }
    }

    private enum WindowKey: Hashable {
        case external(ExternalKey)
        case own(ObjectIdentifier)
    }

    @MainActor
    private enum Surface {
        case external(application: AXUIElement, window: AXUIElement)
        case own(NSWindow)

        var isFullScreen: Bool {
            switch self {
            case .external(_, let window): AXWindowAccess.isFullScreen(window)
            case .own(let window): window.styleMask.contains(.fullScreen)
            }
        }

        var canMove: Bool {
            switch self {
            case .external(_, let window):
                AXWindowAccess.isSettable(kAXPositionAttribute, on: window)
            case .own(let window): window.isMovable
            }
        }

        var canResize: Bool {
            switch self {
            case .external(_, let window):
                AXWindowAccess.isSettable(kAXSizeAttribute, on: window)
            case .own(let window): window.styleMask.contains(.resizable)
            }
        }

        func frame(in geometry: AXGeometry) -> CGRect? {
            switch self {
            case .external(_, let window): AXWindowAccess.frame(of: window)
            case .own(let window): geometry.flip(window.frame)
            }
        }

        func suppressEnhancedUserInterface() -> () -> Void {
            guard case .external(let application, _) = self else { return {} }
            return AXWindowAccess.suppressEnhancedUserInterface(on: application)
        }

        func write(
            _ placement: WindowPlacementEngine.Placement, current: CGRect, canResize: Bool,
            canvas: CGRect?, geometry: AXGeometry
        ) -> CGRect? {
            switch self {
            case .external(_, let window):
                AXWindowAccess.write(
                    placement.frame, anchor: placement.anchor, to: window, current: current,
                    canResize: canResize, canvas: canvas)
            case .own(let window):
                Self.writeOwn(
                    placement, to: window, current: current, canResize: canResize,
                    canvas: canvas, geometry: geometry)
            }
        }

        private static func writeOwn(
            _ placement: WindowPlacementEngine.Placement, to window: NSWindow, current: CGRect,
            canResize: Bool, canvas: CGRect?, geometry: AXGeometry
        ) -> CGRect? {
            var target =
                canResize
                ? placement.frame : placement.anchor.place(current.size, in: placement.frame)
            if !canResize, let canvas {
                target = WindowPlacementEngine.clamped(target, into: canvas)
            }
            window.setFrame(geometry.flip(WindowPlacementEngine.rounded(target)), display: true)
            var actual = geometry.flip(window.frame)

            if actual.width > target.width + AXWindowAccess.clampTolerance
                || actual.height > target.height + AXWindowAccess.clampTolerance
            {
                var slot = placement.anchor.place(actual.size, in: placement.frame)
                if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
                window.setFrameOrigin(geometry.flip(WindowPlacementEngine.rounded(slot)).origin)
                actual = geometry.flip(window.frame)
            }
            return actual
        }
    }

    private var memory = WindowActionMemory<WindowKey>()
    private var terminationToken: NotificationToken?
    private var windowCloseToken: NotificationToken?

    init() {
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.memory.forget { key in
                    guard case .external(let external) = key else { return false }
                    return external.pid == pid
                }
            }
        }
        terminationToken = NotificationToken(token, center: NSWorkspace.shared.notificationCenter)

        let closeToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let closed = note.object as? NSWindow else { return }
            let key = WindowKey.own(ObjectIdentifier(closed))
            Task { @MainActor [weak self] in self?.memory.forget(key: key) }
        }
        windowCloseToken = NotificationToken(closeToken, center: .default)
    }

    private struct FocusedWindow {
        let surface: Surface
        let key: WindowKey
    }

    private typealias Resolver = (
        _ current: CGRect, _ screens: [WindowPlacementEngine.Screen],
        _ decision: WindowActionMemory<WindowKey>.Decision
    ) -> WindowPlacementEngine.Placement?

    @discardableResult
    func perform(
        _ command: WindowCommand.ID, target: WindowTarget?, gap: CGFloat, cycle: WindowCycle
    ) -> Bool {
        guard let catalogued = WindowCommandCatalog.command(id: command),
            let focused = focusedWindow(of: target)
        else { return false }

        if catalogued.kind == .fullscreen {
            guard toggleFullScreen(focused.surface) else { return false }
            memory.forgetCycle(key: focused.key)
            return true
        }
        return place(
            focused, command: command, gap: gap,
            cycleLength: {
                WindowPlacementEngine.cycleLength(for: command, screens: $0, cycle: cycle)
            }
        ) { current, screens, decision in
            WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(
                    command: command, windowFrame: current, screens: screens, gap: gap,
                    step: decision.step, cycle: cycle, originScreenID: decision.originScreenID,
                    restoreFrame: decision.canRestore ? decision.restoreFrame : nil,
                    lastTileCommand: decision.lastTileCommand))
        }
    }

    @discardableResult
    func perform(_ size: CustomWindowSize, target: WindowTarget?, gap: CGFloat) -> Bool {
        guard let focused = focusedWindow(of: target) else { return false }
        return place(
            focused, command: nil, gap: gap, cycleLength: { _ in 1 },
            resolve: { current, screens, _ in
                size.placement(for: current, screens: screens, gap: gap)
            })
    }

    private func focusedWindow(of target: WindowTarget?) -> FocusedWindow? {
        switch target {
        case .own(let window):
            guard window.isVisible else { return nil }
            return FocusedWindow(surface: .own(window), key: .own(ObjectIdentifier(window)))
        case .external(let app):
            guard Permissions.ensureAccessibility() else { return nil }
            guard !app.isTerminated,
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return nil }

            let application = AXWindowAccess.application(for: app.processIdentifier)
            guard let window = AXWindowAccess.targetWindow(in: application) else { return nil }
            AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
            return FocusedWindow(
                surface: .external(application: application, window: window),
                key: .external(ExternalKey(pid: app.processIdentifier, element: window)))
        case nil:
            return nil
        }
    }

    private func place(
        _ focused: FocusedWindow, command: WindowCommand.ID?, gap: CGFloat,
        cycleLength: ([WindowPlacementEngine.Screen]) -> Int, resolve: Resolver
    ) -> Bool {
        let surface = focused.surface
        let geometry = AXGeometry(screens: NSScreen.screens)
        guard !surface.isFullScreen, let current = surface.frame(in: geometry) else { return false }

        let screens = AXScreens.converted(NSScreen.screens, geometry: geometry)
        guard let host = WindowPlacementEngine.screen(containing: current, in: screens) else {
            return false
        }

        let now = Date()
        let decision = memory.decide(
            key: focused.key, command: command, currentFrame: current, currentScreenID: host.id,
            cycleLength: cycleLength(screens), now: now)
        guard let placement = resolve(current, screens, decision) else { return false }

        guard surface.canMove else { return false }
        let canResize = placement.resizes && surface.canResize

        let destination = screens.first { $0.id == placement.screenID }
        let canvas = destination.map {
            WindowPlacementEngine.canvas(
                $0.visibleFrame,
                gap: WindowPlacementEngine.sanitizedGap(gap, in: $0.visibleFrame))
        }
        let restoreEnhancedUI = canResize ? surface.suppressEnhancedUserInterface() : {}
        defer { restoreEnhancedUI() }

        guard
            let applied = surface.write(
                placement, current: current, canResize: canResize, canvas: canvas,
                geometry: geometry)
        else { return false }

        let landedOn =
            WindowPlacementEngine.screen(containing: applied, in: screens)?.id
            ?? placement.screenID
        memory.commit(
            key: focused.key, command: command, decision: decision, appliedFrame: applied,
            screenID: landedOn, now: now)
        return !applied.equalTo(current)
    }

    private func toggleFullScreen(_ surface: Surface) -> Bool {
        switch surface {
        case .own(let window):
            // AppKit fullscreens any resizable window unless it opts out, as the Notes panel does.
            guard window.styleMask.contains(.resizable),
                window.collectionBehavior.isDisjoint(with: [.fullScreenAuxiliary, .fullScreenNone])
            else { return false }
            window.toggleFullScreen(nil)
            return true
        case .external(_, let window):
            let target: CFBoolean =
                AXWindowAccess.isFullScreen(window) ? kCFBooleanFalse : kCFBooleanTrue
            if AXWindowAccess.isSettable(
                AXWindowAccess.fullScreenAttribute as String, on: window),
                AXUIElementSetAttributeValue(
                    window, AXWindowAccess.fullScreenAttribute, target) == .success
            {
                return true
            }
            guard
                let button = AXWindowAccess.element(
                    window, AXWindowAccess.fullScreenButtonAttribute as String)
            else { return false }
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }
    }
}
