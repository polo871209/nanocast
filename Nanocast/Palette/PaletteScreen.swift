import QuartzCore
import SwiftUI

enum PaletteAxis {
    case vertical
    case horizontal
}

@MainActor struct MenuPanelMotion {
    let entryScale: CGFloat
    let maximumScale: CGFloat
    let exitScaleDelta: CGFloat
    let expansionDuration: TimeInterval
    let settleDuration: TimeInterval
    let exitDuration: TimeInterval
    let expansionTiming: CAMediaTimingFunction
    let settleTiming: CAMediaTimingFunction
    let exitTiming: CAMediaTimingFunction

    static let palette = MenuPanelMotion(
        entryScale: Theme.MenuMotion.entryScale,
        maximumScale: Theme.MenuMotion.maximumScale,
        exitScaleDelta: Theme.MenuMotion.exitScaleDelta,
        expansionDuration: Theme.MenuMotion.expansionDuration,
        settleDuration: Theme.MenuMotion.settleDuration,
        exitDuration: Theme.MenuMotion.exitDuration,
        expansionTiming: Theme.MenuMotion.expansionTiming,
        settleTiming: Theme.MenuMotion.settleTiming,
        exitTiming: Theme.MenuMotion.exitTiming)
}

typealias MenuPanelClipPath =
    @MainActor (
        _ bounds: CGRect, _ metrics: InterfaceMetrics, _ corner: MenuPanelCorner
    ) -> CGPath

@MainActor struct PaletteMenuContent {
    let rowCount: Int
    let preferredSelection: Int?
    let isSelectable: (Int) -> Bool
    let clipPath: MenuPanelClipPath
    let motion: MenuPanelMotion
    let view: (MenuPanelCorner) -> AnyView
    let activate: (Int) -> Void

    init(
        rowCount: Int, preferredSelection: Int? = nil,
        view: @escaping (MenuPanelCorner) -> AnyView,
        activate: @escaping (Int) -> Void,
        isSelectable: @escaping (Int) -> Bool = { _ in true },
        clipPath: @escaping MenuPanelClipPath,
        motion: MenuPanelMotion
    ) {
        self.rowCount = rowCount
        self.preferredSelection = preferredSelection
        self.view = view
        self.activate = activate
        self.isSelectable = isSelectable
        self.clipPath = clipPath
        self.motion = motion
    }

    init(
        popover: PopoverMenuContent, selection: Binding<Int>, width: CGFloat? = nil,
        visibleRows: CGFloat? = nil,
        search: PopoverMenu.Search, onActivate: @escaping (Int) -> Void,
        preferredSelection: Int? = nil, extraRowsHeight: CGFloat = 0
    ) {
        self.init(
            rowCount: popover.items.count, preferredSelection: preferredSelection,
            view: { corner in
                AnyView(
                    PopoverMenu(
                        header: popover.header, items: popover.items, selection: selection,
                        width: width, visibleRows: visibleRows, onActivate: onActivate,
                        attachment: corner.popoverAttachment, search: search,
                        extraRowsHeight: extraRowsHeight))
            },
            activate: { popover.items[$0].action() },
            isSelectable: { popover.items[$0].isSelectable },
            clipPath: { bounds, metrics, corner in
                PopoverMenu.SurfaceShape(
                    attachment: corner.popoverAttachment, radius: metrics.radius.menuPanel,
                    attachedRadius: metrics.size.menuButton / 2
                ).path(in: bounds).cgPath
            },
            motion: .palette)
    }
}

private extension MenuPanelCorner {
    var popoverAttachment: PopoverMenu.Attachment {
        switch self {
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        case .belowHeaderTrailing, .belowControl: .none
        }
    }
}

@MainActor protocol PaletteScreen {
    associatedtype Row: Identifiable

    var rows: [Row] { get }
    var primaryActionTitle: String { get }
    var hidesSearchField: Bool { get }
    var actsWithoutRows: Bool { get }
    var landingSelection: Int { get }

    func hasPrimaryAction(at selection: Int) -> Bool
    func isPrimaryActionEnabled(at selection: Int) -> Bool
    func hasActions(at selection: Int) -> Bool
    func ownsVerticalKeys(at selection: Int) -> Bool
    func tabTarget(from selection: Int, backwards: Bool) -> Int?
    func tab(at selection: Int, backwards: Bool) -> Bool
    func actions(at selection: Int) -> PopoverMenuContent?
    func activate(at selection: Int)
    func secondary(at selection: Int) -> Bool
    func tertiary(at selection: Int) -> Bool
    func pasteKeepingWindowOpen(at selection: Int) -> Bool
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int?
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    @ViewBuilder func body(selection: Int, scroll: ScrollIntent) -> AnyView
}

extension PaletteScreen {
    func hasPrimaryAction(at selection: Int) -> Bool { true }
    func isPrimaryActionEnabled(at selection: Int) -> Bool { true }
    func hasActions(at selection: Int) -> Bool { true }
    var hidesSearchField: Bool { false }
    var actsWithoutRows: Bool { false }
    var landingSelection: Int { 0 }
    func ownsVerticalKeys(at selection: Int) -> Bool { false }
    func tabTarget(from selection: Int, backwards: Bool) -> Int? { nil }
    func tab(at selection: Int, backwards: Bool) -> Bool { false }
    func actions(at selection: Int) -> PopoverMenuContent? { nil }
    func tertiary(at selection: Int) -> Bool { false }
    func pasteKeepingWindowOpen(at selection: Int) -> Bool { false }
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool { false }
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? { nil }
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    { nil }
}

extension PopoverMenuContent {
    func matching(
        _ query: ActionMenuSearchQuery
    ) -> (
        content: PopoverMenuContent, bestMatch: Int?
    ) {
        guard !query.isEmpty else { return (self, nil) }
        var pendingSection = false
        var pendingTitle: String?
        var matches: [PopoverMenuItem] = []
        var bestMatch: (index: Int, score: Int)?

        for original in items {
            if original.startsSection {
                pendingSection = true
                pendingTitle = nil
            }
            if let sectionTitle = original.sectionTitle { pendingTitle = sectionTitle }
            guard let score = query.score(original.title) else { continue }

            var item = original
            item.startsSection = pendingSection && !matches.isEmpty
            item.sectionTitle = pendingTitle
            pendingSection = false
            pendingTitle = nil
            matches.append(item)
            if item.isSelectable, score > (bestMatch?.score ?? .min) {
                bestMatch = (matches.count - 1, score)
            }
        }
        return (PopoverMenuContent(header: header, items: matches), bestMatch?.index)
    }
}

struct PaletteHeaderAccessory {
    let width: CGFloat
    let fieldNames: [String]
    let firstIncompleteField: String?
    let view: AnyView

    func field(after current: String?, backwards: Bool) -> String? {
        guard let current, let index = fieldNames.firstIndex(of: current) else {
            return backwards ? fieldNames.last : fieldNames.first
        }
        let next = index + (backwards ? -1 : 1)
        return fieldNames.indices.contains(next) ? fieldNames[next] : nil
    }
}
