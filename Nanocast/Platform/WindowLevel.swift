import AppKit

extension NSWindow.Level {
    static let palette = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
    static let paletteDropGuide = NSWindow.Level(rawValue: palette.rawValue - 1)
    static let dialog = NSWindow.Level(rawValue: palette.rawValue + 1)
}
