import Foundation

@MainActor
final class WindowShortcutPresetCoordinator {
    private let hotKeys: HotKeyManager
    private unowned let core: AppCore

    init(hotKeys: HotKeyManager, core: AppCore) {
        self.hotKeys = hotKeys
        self.core = core
    }

    var matchingPreset: WindowShortcutPreset? {
        WindowShortcutPreset.matching(currentBindings())
    }

    func apply(_ preset: WindowShortcutPreset) async {
        var current = currentBindings()
        var plan = WindowShortcutPresetPlan(preset: preset, current: current)
        guard !plan.assignments.isEmpty else {
            core.showMessage("\(preset.title) shortcuts already set")
            return
        }
        if !plan.overwritten.isEmpty {
            let confirmed = Set(plan.overwritten)
            guard
                await core.confirm(
                    title: plan.overwritten.count == 1
                        ? "Replace 1 shortcut?" : "Replace \(plan.overwritten.count) shortcuts?",
                    message: replacementMessage(plan.overwritten, preset: preset),
                    symbol: "keyboard", confirmTitle: "Replace")
            else { return }
            current = currentBindings()
            plan = WindowShortcutPresetPlan(preset: preset, current: current)
            guard Set(plan.overwritten).isSubset(of: confirmed) else { return await apply(preset) }
        }
        for id in plan.displaced + plan.assignments.keys where current[id] != nil {
            hotKeys.setBinding(nil, for: .windowCommand(id: id))
        }
        var skipped: [WindowCommand.ID] = []
        for id in WindowCommand.ID.allCases {
            guard let binding = plan.assignments[id] else { continue }
            let action = HotKeyAction.windowCommand(id: id)
            guard hotKeys.conflictOwner(of: binding, excluding: action) == nil else {
                skipped.append(id)
                continue
            }
            hotKeys.setBinding(binding, for: action)
        }
        for id in skipped {
            let action = HotKeyAction.windowCommand(id: id)
            if let previous = current[id],
                hotKeys.conflictOwner(of: previous, excluding: action) == nil
            {
                hotKeys.setBinding(previous, for: action)
            }
        }
        if skipped.isEmpty {
            core.showMessage("Applied \(preset.title) shortcuts")
        } else {
            core.showMessage(
                "Applied \(preset.title) shortcuts — \(skipped.count) skipped, keys in use",
                tone: .danger)
        }
    }

    private func currentBindings() -> [WindowCommand.ID: HotKeyBinding] {
        var current: [WindowCommand.ID: HotKeyBinding] = [:]
        for id in WindowCommand.ID.allCases {
            current[id] = hotKeys.binding(for: .windowCommand(id: id))
        }
        return current
    }

    private func replacementMessage(
        _ ids: [WindowCommand.ID], preset: WindowShortcutPreset
    ) -> String {
        let names = ids.compactMap { WindowCommandCatalog.command(id: $0)?.name }
        guard names.count > 3 else {
            let listed = names.formatted(.list(type: .and))
            return "\(listed) will use the \(preset.title) keys instead of the ones you set."
        }
        let listed = names.prefix(3).joined(separator: ", ")
        let more = names.count - 3
        return """
            \(listed) and \(more) more will use the \(preset.title) keys instead of the ones you set.
            """
    }
}
