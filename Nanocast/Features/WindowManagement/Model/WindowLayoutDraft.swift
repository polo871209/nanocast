import CoreGraphics
import Foundation

@MainActor
@Observable
final class WindowLayoutDraft {
    static let percentRange: ClosedRange<Int> = 5...100
    static let offsetRange: ClosedRange<Int> = -4000...4000

    let existingID: UUID?
    var name: String
    var iconSymbol: String?
    var usesPreferredGap: Bool
    private(set) var entries: [WindowLayoutEntry]
    private var frontmostEntryID: UUID?
    private(set) var selectedEntryID: UUID?
    private(set) var selectedDisplayUUID: String?

    init(layout: WindowLayout?, displays: [WindowLayoutDisplay]) {
        existingID = layout?.id
        name = layout?.name ?? ""
        iconSymbol = layout?.iconSymbol
        usesPreferredGap = layout?.usesPreferredGap ?? true
        entries = layout?.entries ?? []
        frontmostEntryID = layout?.frontmostEntryID
        selectedEntryID = entries.first?.id
        selectedDisplayUUID = entries.first?.display.uuid ?? displays.first?.uuid
    }

    var symbol: String { iconSymbol ?? WindowLayout.sfSymbol }
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !entries.isEmpty
    }

    var selectedEntry: WindowLayoutEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    var isSelectedEntryFrontmost: Bool {
        get { selectedEntryID != nil && frontmostEntryID == selectedEntryID }
        set {
            guard let id = selectedEntryID else { return }
            if newValue {
                frontmostEntryID = id
            } else if frontmostEntryID == id {
                frontmostEntryID = nil
            }
        }
    }

    func entries(onDisplay uuid: String) -> [WindowLayoutEntry] {
        entries.filter { $0.display.uuid == uuid }
    }

    func tabs(connected: [WindowLayoutDisplay]) -> [WindowLayoutDisplay] {
        var seen = Set(connected.map(\.uuid))
        var result = connected
        for entry in entries where seen.insert(entry.display.uuid).inserted {
            result.append(entry.display)
        }
        return result
    }

    func select(entryID: UUID) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }
        selectedEntryID = entryID
        selectedDisplayUUID = entry.display.uuid
    }

    func select(displayUUID: String) {
        selectedDisplayUUID = displayUUID
        if selectedEntry?.display.uuid != displayUUID {
            selectedEntryID = entries(onDisplay: displayUUID).first?.id
        }
    }

    func addEntry(bundleID: String, on display: WindowLayoutDisplay) {
        let entry = WindowLayoutEntry(bundleID: bundleID, display: display)
        entries.append(entry)
        select(entryID: entry.id)
    }

    func removeSelectedEntry() {
        guard let id = selectedEntryID else { return }
        entries.removeAll { $0.id == id }
        if frontmostEntryID == id { frontmostEntryID = nil }
        selectedEntryID =
            selectedDisplayUUID.flatMap { entries(onDisplay: $0).first?.id }
            ?? entries.first?.id
    }

    func setArgument(_ argument: String?) {
        update { $0.argument = argument?.isEmpty == true ? nil : argument }
    }

    func setAnchor(_ anchor: WindowLayoutAnchor) {
        update { $0.anchor = anchor }
    }

    func setWidthPercent(_ percent: Int) {
        update { $0.widthFraction = Self.fraction(percent) }
    }

    func setHeightPercent(_ percent: Int) {
        update { $0.heightFraction = Self.fraction(percent) }
    }

    func setOffsetX(_ points: Int) {
        update { $0.offset.x = CGFloat(points.clamped(to: Self.offsetRange)) }
    }

    func setOffsetY(_ points: Int) {
        update { $0.offset.y = CGFloat(points.clamped(to: Self.offsetRange)) }
    }

    var previewLayout: WindowLayout {
        WindowLayout(
            id: existingID ?? UUID(), name: name, iconSymbol: iconSymbol,
            usesPreferredGap: usesPreferredGap, entries: entries,
            frontmostEntryID: frontmostEntryID)
    }

    func layout() -> WindowLayout {
        var value = previewLayout
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    static func percent(_ fraction: CGFloat) -> Int {
        guard fraction.isFinite else { return 100 }
        return Int((fraction * 100).rounded()).clamped(to: percentRange)
    }

    private static func fraction(_ percent: Int) -> CGFloat {
        CGFloat(percent.clamped(to: percentRange)) / 100
    }

    private func update(_ change: (inout WindowLayoutEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == selectedEntryID }) else { return }
        change(&entries[index])
    }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
