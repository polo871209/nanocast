import AppKit

@MainActor
final class ColorPickerCoordinator {
    private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
    }

    func pick() {
        if core.paletteCoordinator.isVisible { core.paletteCoordinator.hidePalette(restoreFocus: false) }
        Task {
            guard let color = await NSColorSampler().sample()?.usingColorSpace(.sRGB) else { return }
            let hex = ColorFormat.hex.string(
                for: ColorValue(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent))
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(hex, forType: .string)
            core.showMessage("Copied \(hex)")
        }
    }
}
