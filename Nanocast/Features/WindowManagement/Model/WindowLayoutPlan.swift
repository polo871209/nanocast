import CoreGraphics
import Foundation

struct WindowLayoutScreen: Equatable, Sendable {
    var display: WindowLayoutDisplay
    var screen: WindowPlacementEngine.Screen
}

struct WindowLayoutWindow: Equatable, Sendable {
    var handle: Int
    var bundleID: String
    var frame: CGRect
    var title: String

    init(handle: Int, bundleID: String, frame: CGRect, title: String = "") {
        self.handle = handle
        self.bundleID = bundleID
        self.frame = frame
        self.title = title
    }
}

struct WindowLayoutPlan: Equatable, Sendable {
    enum Skip: Equatable, Sendable {
        case displayDisconnected(name: String)
        case unresolvableGeometry
        case duplicateTarget
    }

    enum Source: Equatable, Sendable {
        case existing(handle: Int)
        case launch
    }

    struct Placement: Equatable, Sendable {
        var entryID: UUID
        var bundleID: String
        var argument: String?
        var source: Source
        var frame: CGRect
        var screenID: Int
        var anchor: WindowLayoutAnchor
        var canvas: CGRect
    }

    struct Skipped: Equatable, Sendable {
        var entryID: UUID
        var reason: Skip
    }

    var placements: [Placement]
    var skipped: [Skipped]
    var frontmostEntryID: UUID?

    var opens: [Placement] { placements.filter { $0.source == .launch } }

    var skippedSummary: String? {
        guard !skipped.isEmpty else { return nil }
        let displays = Set(
            skipped.compactMap { skip -> String? in
                guard case .displayDisconnected(let name) = skip.reason else { return nil }
                return name
            })
        if !displays.isEmpty, displays.count == skipped.count {
            return displays.count == 1 ? "1 display not connected" : "\(displays.count) displays not connected"
        }
        return skipped.count == 1 ? "1 entry skipped" : "\(skipped.count) entries skipped"
    }

    static func make(
        layout: WindowLayout, screens: [WindowLayoutScreen], windows: [WindowLayoutWindow],
        preferredGap: CGFloat
    ) -> WindowLayoutPlan {
        let gap = layout.usesPreferredGap ? preferredGap : 0
        var screensByUUID: [String: WindowLayoutScreen] = [:]
        for screen in screens where screensByUUID[screen.display.uuid.lowercased()] == nil {
            screensByUUID[screen.display.uuid.lowercased()] = screen
        }
        var available = Dictionary(grouping: sorted(windows), by: \.bundleID)
        var launched: Set<String> = []
        var placements: [Placement] = []
        var skipped: [Skipped] = []

        for entry in layout.entries {
            guard let target = screensByUUID[entry.display.uuid.lowercased()] else {
                skipped.append(
                    Skipped(
                        entryID: entry.id, reason: .displayDisconnected(name: entry.display.name)))
                continue
            }
            guard
                let frame = WindowLayoutGeometry.resolve(entry, on: target.screen, gap: gap)
            else {
                skipped.append(Skipped(entryID: entry.id, reason: .unresolvableGeometry))
                continue
            }

            let source: Source
            if entry.argument == nil,
                let index = nearest(to: frame, among: available[entry.bundleID] ?? [])
            {
                source = .existing(handle: available[entry.bundleID]!.remove(at: index).handle)
            } else {
                let key = entry.bundleID + "\u{0}" + (entry.argument ?? "")
                guard launched.insert(key).inserted else {
                    skipped.append(Skipped(entryID: entry.id, reason: .duplicateTarget))
                    continue
                }
                source = .launch
            }

            placements.append(
                Placement(
                    entryID: entry.id, bundleID: entry.bundleID, argument: entry.argument,
                    source: source, frame: frame, screenID: target.screen.id, anchor: entry.anchor,
                    canvas: WindowLayoutGeometry.box(target.screen, gap: gap)))
        }
        let frontmost = placements.first { $0.entryID == layout.frontmostEntryID }?.entryID
        return WindowLayoutPlan(
            placements: placements, skipped: skipped, frontmostEntryID: frontmost)
    }

    private static func nearest(to frame: CGRect, among windows: [WindowLayoutWindow]) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, window) in windows.enumerated() {
            let distance =
                abs(window.frame.midX - frame.midX) + abs(window.frame.midY - frame.midY)
            if distance < (best?.distance ?? .infinity) { best = (index, distance) }
        }
        return best?.index
    }

    private static func sorted(_ windows: [WindowLayoutWindow]) -> [WindowLayoutWindow] {
        windows.sorted {
            if $0.frame.minY != $1.frame.minY { return $0.frame.minY < $1.frame.minY }
            if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.handle < $1.handle
        }
    }
}
