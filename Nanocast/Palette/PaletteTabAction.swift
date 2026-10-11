import Foundation

enum PaletteTabAction {
    static func destination(from mode: PaletteMode, clipboardEnabled: Bool) -> PaletteMode {
        mode == .launcher && clipboardEnabled ? .clipboard : .launcher
    }
}
