import Carbon.HIToolbox
import Foundation

@main
@MainActor
struct PaletteEscapeTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ actual: PaletteEscapeAction, _ expected: PaletteEscapeAction, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func expectChord(_ actual: Bool, _ expected: Bool, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func resolve(
        menuOpen: Bool = false, menuQuery: String = "", argumentFocused: Bool = false,
        query: String = "", canGoBack: Bool = false,
        behavior: EscapeKeyBehavior = .navigateBackOrClose
    ) -> PaletteEscapeAction {
        PaletteEscapeAction.resolve(
            menuOpen: menuOpen, menuQuery: menuQuery, argumentFocused: argumentFocused,
            query: query, canGoBack: canGoBack, behavior: behavior)
    }

    static func main() {
        expect(
            resolve(menuOpen: true, menuQuery: "paste"),
            .clearMenuQuery,
            "an open menu clears its own query before it closes")
        expect(
            resolve(menuOpen: true, query: "notes"),
            .closeMenu,
            "an open menu closes before anything else")
        expect(
            resolve(query: "notes"),
            .clearQuery,
            "a typed launcher query clears before the palette hides")
        expect(
            resolve(),
            .hidePalette,
            "an empty launcher query hides the palette")

        expect(
            resolve(canGoBack: true),
            .goBack,
            "a screen opened from the root search returns to it")
        expect(
            resolve(query: "notes", canGoBack: true),
            .clearQuery,
            "a typed query still clears before the back step it would otherwise skip")

        expect(
            resolve(canGoBack: true, behavior: .closeAndPopToRoot),
            .hidePalette,
            "close-and-pop-to-root hides even where a back step exists")
        expect(
            resolve(query: "notes", behavior: .closeAndPopToRoot),
            .clearQuery,
            "clearing the query is the first press under either behavior")
        expect(
            resolve(menuOpen: true, canGoBack: true, behavior: .closeAndPopToRoot),
            .closeMenu,
            "a menu outranks the behavior setting beneath it")

        expect(
            resolve(argumentFocused: true, query: "search"),
            .leaveArgumentField,
            "an argument field hands focus back before the query that found it clears")
        expect(
            resolve(argumentFocused: true, canGoBack: true),
            .leaveArgumentField,
            "an empty query does not let the argument field skip its own step")
        expect(
            resolve(menuOpen: true, argumentFocused: true, query: "search"),
            .closeMenu,
            "a menu still outranks the argument field beneath it")

        // ⌘⎋ never reaches the responder chain, so what counts as the chord is decided in the tap.
        expectChord(
            CommandEscapeTap.isChord(keyCode: Int64(kVK_Escape), flags: [.maskCommand]),
            true, "a bare ⌘⎋ is the root-search chord")
        expectChord(
            CommandEscapeTap.isChord(keyCode: Int64(kVK_Escape), flags: []),
            false, "an unmodified Escape belongs to the palette's own handler")
        expectChord(
            CommandEscapeTap.isChord(
                keyCode: Int64(kVK_Escape), flags: [.maskCommand, .maskAlternate]),
            false, "⌥⌘⎋ is Force Quit and must pass straight through")
        expectChord(
            CommandEscapeTap.isChord(
                keyCode: Int64(kVK_Escape), flags: [.maskCommand, .maskShift]),
            false, "any further modifier spells somebody else's chord")
        expectChord(
            CommandEscapeTap.isChord(keyCode: Int64(kVK_ANSI_A), flags: [.maskCommand]),
            false, "⌘A is not it")
        // Caps Lock and fn ride along on real hardware without changing which chord was struck.
        expectChord(
            CommandEscapeTap.isChord(
                keyCode: Int64(kVK_Escape), flags: [.maskCommand, .maskAlphaShift, .maskSecondaryFn]),
            true, "the flags a real keyboard adds do not disqualify the chord")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
