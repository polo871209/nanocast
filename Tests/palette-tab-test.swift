import Foundation

@main
@MainActor
struct PaletteTabTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ actual: PaletteMode, _ expected: PaletteMode, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func main() {
        expect(
            PaletteTabAction.destination(from: .launcher, clipboardEnabled: true), .clipboard,
            "the launcher flips to the clipboard")
        expect(
            PaletteTabAction.destination(from: .clipboard, clipboardEnabled: true), .launcher,
            "the clipboard closes the ring")
        expect(
            PaletteTabAction.destination(from: .launcher, clipboardEnabled: false), .launcher,
            "with the clipboard off, the launcher rings back onto itself")

        for mode in [PaletteMode.emoji, .fileSearch, .calculatorHistory, .customCommands] {
            expect(
                PaletteTabAction.destination(from: mode, clipboardEnabled: true), .launcher,
                "\(mode.rawValue) is a sub-screen, so Tab exits to the launcher")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
