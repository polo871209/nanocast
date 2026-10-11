import AppKit
@preconcurrency import ApplicationServices

@MainActor
enum WindowLayoutRunner {
    private static let launchDeadline = Duration.seconds(10)
    private static let pollInterval = Duration.milliseconds(200)

    struct Outcome: Sendable {
        var placed = 0
        var opened = 0
        var skipped: [WindowLayoutPlan.Skipped] = []
        var neverAppeared: [String] = []
        var openFailures: [String] = []
        var isBlockedOnPermission = false

        var didAnything: Bool { placed > 0 }
    }

    static func run(_ layout: WindowLayout, gap: CGFloat) async -> Outcome {
        guard Permissions.ensureAccessibility() else {
            return Outcome(isBlockedOnPermission: true)
        }

        let snapshot = WindowInventory.snapshot()
        let plan = WindowLayoutPlan.make(
            layout: layout, screens: snapshot.screens, windows: snapshot.windows,
            preferredGap: gap)
        var outcome = Outcome(skipped: plan.skipped)
        guard !plan.placements.isEmpty else { return outcome }

        let startingApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var bound: [UUID: WindowInventory.Element] = [:]
        placeExisting(plan, snapshot: snapshot, bound: &bound, outcome: &outcome)

        let pending = plan.opens
        if !pending.isEmpty {
            await open(pending, outcome: &outcome)
            await placeOpened(pending, bound: &bound, outcome: &outcome)
        }
        if !Task.isCancelled, let frontmost = plan.frontmostEntryID.flatMap({ bound[$0] }),
            !userSwitchedApps(since: startingApp, opening: pending)
        {
            AXWindowAccess.focus(frontmost.window, in: frontmost.application, of: frontmost.app)
        }
        return outcome
    }

    private static func userSwitchedApps(
        since startingApp: pid_t?, opening placements: [WindowLayoutPlan.Placement]
    ) -> Bool {
        guard let current = NSWorkspace.shared.frontmostApplication,
            current.processIdentifier != startingApp
        else { return false }
        return !placements.contains { $0.bundleID == current.bundleIdentifier }
    }

    static func captureCurrentWindows() -> (entries: [WindowLayoutEntry], frontmostEntryID: UUID?) {
        guard Permissions.ensureAccessibility() else { return ([], nil) }
        let snapshot = WindowInventory.snapshot(positionableOnly: true)
        let screens = snapshot.screens
        let focusedHandle = focusedWindowHandle(in: snapshot)
        var frontmostEntryID: UUID?
        let entries = snapshot.windows.compactMap { window -> WindowLayoutEntry? in
            guard
                let host = WindowPlacementEngine.screen(
                    containing: window.frame, in: screens.map(\.screen)),
                let target = screens.first(where: { $0.screen.id == host.id })
            else { return nil }
            let entry = WindowLayoutGeometry.entry(
                bundleID: window.bundleID, display: target.display, frame: window.frame,
                on: target.screen)
            if window.handle == focusedHandle { frontmostEntryID = entry.id }
            return entry
        }
        return (entries, frontmostEntryID)
    }

    private static func focusedWindowHandle(in snapshot: WindowInventory.Snapshot) -> Int? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let focused = AXWindowAccess.element(
                AXWindowAccess.application(for: app.processIdentifier),
                kAXFocusedWindowAttribute)
        else { return nil }
        return snapshot.elements.first { _, element in
            element.app.processIdentifier == app.processIdentifier
                && CFEqual(element.window, focused)
        }?.key
    }

    private static func placeExisting(
        _ plan: WindowLayoutPlan, snapshot: WindowInventory.Snapshot,
        bound: inout [UUID: WindowInventory.Element], outcome: inout Outcome
    ) {
        let existing = plan.placements.filter { $0.source != .launch }
        for (_, group) in Dictionary(grouping: existing, by: \.bundleID) {
            guard case .existing(let first) = group[0].source,
                let application = snapshot.elements[first]?.application
            else { continue }
            let restore = AXWindowAccess.suppressEnhancedUserInterface(on: application)
            defer { restore() }
            for placement in group {
                guard case .existing(let handle) = placement.source,
                    let element = snapshot.elements[handle]
                else { continue }
                if place(placement, on: element.window) { outcome.placed += 1 }
                bound[placement.entryID] = element
            }
        }
    }

    private static func place(
        _ placement: WindowLayoutPlan.Placement, on window: AXUIElement
    ) -> Bool {
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
        guard AXWindowAccess.isSettable(kAXPositionAttribute, on: window),
            let current = AXWindowAccess.frame(of: window)
        else { return false }
        let canResize = AXWindowAccess.isSettable(kAXSizeAttribute, on: window)
        return AXWindowAccess.write(
            placement.frame, anchor: placement.anchor.placement, to: window, current: current,
            canResize: canResize, canvas: placement.canvas) != nil
    }

    private static func open(
        _ placements: [WindowLayoutPlan.Placement], outcome: inout Outcome
    ) async {
        for placement in placements {
            guard
                let url = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: placement.bundleID)
            else {
                outcome.openFailures.append(placement.bundleID)
                continue
            }
            guard let argument = placement.argument else {
                AppLauncher.launch(url)
                outcome.opened += 1
                continue
            }
            guard let target = argumentURL(argument) else {
                outcome.openFailures.append(argument)
                continue
            }
            do {
                _ = try await NSWorkspace.shared.open(
                    [target], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
                outcome.opened += 1
            } catch {
                outcome.openFailures.append(error.localizedDescription)
            }
        }
    }

    private static func argumentURL(_ argument: String) -> URL? {
        switch LinkDestination.detect(argument) {
        case .web(let url), .network(let url), .deeplink(let url): url
        case .path(let path):
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        case nil: nil
        }
    }

    private static func placeOpened(
        _ placements: [WindowLayoutPlan.Placement],
        bound: inout [UUID: WindowInventory.Element], outcome: inout Outcome
    ) async {
        var pending = placements
        let deadline = ContinuousClock.now + launchDeadline
        while !pending.isEmpty, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: pollInterval, tolerance: pollInterval)
            guard !Task.isCancelled else { break }
            pending = pending.filter { placement in
                guard let (application, app) = WindowInventory.application(for: placement.bundleID),
                    let window = WindowInventory.unclaimedWindows(
                        of: application, excluding: bound.values.lazy.map(\.window)
                    ).first
                else { return true }
                let restore = AXWindowAccess.suppressEnhancedUserInterface(on: application)
                defer { restore() }
                if place(placement, on: window) { outcome.placed += 1 }
                bound[placement.entryID] = WindowInventory.Element(
                    bundleID: placement.bundleID, app: app, application: application,
                    window: window)
                return false
            }
        }
        outcome.neverAppeared = pending.map(\.bundleID)
    }
}
