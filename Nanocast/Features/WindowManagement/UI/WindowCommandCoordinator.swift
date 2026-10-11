import AppKit

@MainActor
final class WindowCommandCoordinator {
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    private let windowMover: WindowMover
    private let spaceSwitcher: SpaceSwitcher
    private let customSizes: CustomWindowSizeStore

    init(
        settings: AppSettings, paletteCoordinator: PaletteCoordinator, windowMover: WindowMover,
        spaceSwitcher: SpaceSwitcher, customSizes: CustomWindowSizeStore
    ) {
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.windowMover = windowMover
        self.spaceSwitcher = spaceSwitcher
        self.customSizes = customSizes
    }

    func runWindowCommand(id: WindowCommand.ID) {
        guard settings.windowManagementEnabled else { return }
        if let direction = SpaceDirection(id) {
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
            spaceSwitcher.perform(direction)
            return
        }
        windowMover.perform(
            id, target: handOffTarget(), gap: CGFloat(settings.windowGap),
            cycle: settings.windowCycle)
    }

    func runCustomWindowSize(id: UUID) {
        guard settings.windowManagementEnabled, let size = customSizes.size(id: id) else { return }
        windowMover.perform(size, target: handOffTarget(), gap: CGFloat(settings.windowGap))
    }

    private func handOffTarget() -> WindowTarget? {
        guard paletteCoordinator.isVisible else { return WindowTarget.current() }
        let target = WindowTarget.behindPalette(
            ownWindow: paletteCoordinator.previousOwnWindow, app: paletteCoordinator.targetApp)
        paletteCoordinator.hidePalette(restoreFocus: true)
        return target
    }
}
