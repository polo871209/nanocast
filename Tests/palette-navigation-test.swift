import CoreGraphics
import Foundation

@main
@MainActor
struct PaletteNavigationTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func searchingLauncher() -> PaletteState {
        let vm = PaletteState()
        vm.prepare(mode: .launcher)
        vm.query = "clipboard"
        vm.selection = 3
        return vm
    }

    static func main() {
        openingDisarmed()
        deliberateMovementArms()
        scrollingDisarms()
        driftDoesNotRearm()
        theDisarmTokenClearsLitRows()

        let vm = searchingLauncher()
        expect(!vm.canGoBack, "a prepared screen is a root with nothing behind it")

        vm.push(mode: .clipboard)
        expect(
            vm.mode == .clipboard && vm.query.isEmpty && vm.selection == 0,
            "a pushed screen opens as fresh as a prepared one")
        expect(vm.canGoBack, "the screen it was pushed over is still there to return to")

        vm.emojiCategoryFilter = .pinned
        vm.emojiGridColumnsOverride = .six

        expect(vm.pop(), "a pushed screen has a step back")
        expect(
            vm.mode == .launcher && vm.query == "clipboard" && vm.selection == 3,
            "the back step restores the screen, its query and its selection")
        expect(!vm.canGoBack, "the restored screen is the root again")
        expect(!vm.pop(), "a root has nowhere left to go")
        expect(
            vm.mode == .launcher && vm.query == "clipboard",
            "a refused back step leaves the screen untouched")

        let freshEmoji = searchingLauncher()
        freshEmoji.emojiCategoryFilter = .category(.flags)
        freshEmoji.emojiGridColumnsOverride = .ten
        freshEmoji.prepare(mode: .emoji)
        expect(
            freshEmoji.emojiCategoryFilter == .all && freshEmoji.emojiGridColumnsOverride == nil,
            "a fresh emoji screen restores all categories and the configured grid default")

        let tokens = searchingLauncher()
        tokens.push(mode: .emoji)
        let reset = tokens.resetToken
        let follow = tokens.followToken
        expect(tokens.pop(), "the emoji screen goes back to the launcher")
        expect(tokens.resetToken == reset, "a back step does not snap the restored list to the top")
        expect(tokens.followToken != follow, "it scrolls the restored row into view instead")

        let command = searchingLauncher()
        command.query = "Create Custom Command"
        command.push(mode: .customCommandEditor)
        command.noteEditingField(true)
        expect(
            command.mode.isNativeEditor && command.query.isEmpty,
            "the command editor owns its keyboard without inheriting the launcher query")
        expect(
            command.pop(preservingSelection: true) && command.mode == .launcher
                && command.query == "Create Custom Command" && command.restoredSelection == 3
                && !command.isEditingField,
            "leaving a command editor restores the launcher query and selected row")
        command.prepare(mode: .customCommandEditor)
        expect(!command.canGoBack, "a command editor summoned directly starts without a previous screen")

        let commands = searchingLauncher()
        commands.push(mode: .customCommands)
        commands.query = "Screens"
        commands.selection = 2
        commands.push(mode: .customCommandEditor)
        commands.noteEditingField(true)
        expect(
            commands.pop(preservingSelection: true) && commands.mode == .customCommands
                && commands.query == "Screens" && commands.restoredSelection == 2
                && !commands.isEditingField,
            "closing a command editor restores its browser query and selection")
        commands.query = "new search"
        expect(commands.restoredSelection == nil, "typing a new query releases the restored selection")
        expect(commands.pop() && commands.mode == .launcher, "the command browser returns to root search")
        commands.prepare(mode: .customCommands)
        expect(commands.restoredSelection == nil, "a fresh summon releases the restored selection")
        expect(
            !PaletteMode.customCommands.isNativeEditor,
            "native editor keyboard routing excludes browsers")

        let switched = searchingLauncher()
        switched.push(mode: .customCommandEditor)
        switched.push(mode: .clipboard)
        expect(
            switched.pop() && switched.mode == .launcher && switched.query == "clipboard"
                && !switched.canGoBack,
            "switching away from an editor never restores it without its session")
        switched.prepare(mode: .customCommandEditor)
        switched.push(mode: .clipboard)
        expect(!switched.canGoBack, "a directly summoned editor leaves no dead back frame")

        let summoned = searchingLauncher()
        summoned.push(mode: .clipboard)
        summoned.prepare(mode: .emoji)
        expect(!summoned.canGoBack, "a summon is a new root, not a step onto the old stack")

        let ringed = searchingLauncher()
        ringed.push(mode: .clipboard)
        ringed.resetNavigation()
        expect(
            !ringed.canGoBack && ringed.mode == .clipboard,
            "closing the Tab ring drops the stack without disturbing the screen")

        let hopped = searchingLauncher()
        hopped.pushCarryingQuery(mode: .clipboard)
        expect(
            hopped.mode == .clipboard && hopped.query == "clipboard" && hopped.selection == 3,
            "a ring hop carries the query and the row it was on")
        expect(
            hopped.pop() && hopped.mode == .launcher && hopped.query == "clipboard",
            "and the screen it crossed from is the step back")

        let pasted = searchingLauncher()
        pasted.query = "\nfirst pasted row,\r\nsecond pasted row\u{2028}third\n"
        expect(
            pasted.collapseQueryLineBreaks() && pasted.query == "first pasted row, second pasted row third",
            "a multi-line paste collapses to one line with no edge breaks")
        expect(
            !pasted.collapseQueryLineBreaks() && pasted.query == "first pasted row, second pasted row third",
            "a single-line query is left alone")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static let rest = CGPoint(x: 400, y: 300)

    static func shown() -> PaletteState {
        let state = PaletteState()
        state.disarmHoverHighlight(pointerAt: rest)
        return state
    }

    static func armed() -> PaletteState {
        let state = shown()
        state.notePointerMoved(to: CGPoint(x: rest.x + 40, y: rest.y))
        return state
    }

    static func openingDisarmed() {
        let state = shown()
        expect(!state.hoverHighlightArmed, "a palette just shown is disarmed")
        state.notePointerMoved(to: rest)
        expect(!state.hoverHighlightArmed, "a mouse-moved event that has not moved arms nothing")
        let state2 = armed()
        state2.prepare(mode: .clipboard)
        expect(!state2.hoverHighlightArmed, "switching mode disarms the highlight again")
    }

    static func deliberateMovementArms() {
        expect(armed().hoverHighlightArmed, "a pointer moved across the panel arms the highlight")

        let diagonal = shown()
        diagonal.notePointerMoved(to: CGPoint(x: rest.x + 3, y: rest.y + 3))
        expect(diagonal.hoverHighlightArmed, "movement is measured as a distance, not per axis")

        let creeping = shown()
        for step in 1...4 {
            creeping.notePointerMoved(to: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
        }
        expect(creeping.hoverHighlightArmed, "and it accumulates: the anchor holds while it moves")
    }

    static func scrollingDisarms() {
        let scrolled = armed()
        scrolled.disarmHoverHighlight(pointerAt: rest)
        expect(!scrolled.hoverHighlightArmed, "a scroll drops the highlight")

        let stillScrolling = armed()
        for step in 1...20 {
            stillScrolling.disarmHoverHighlight(
                pointerAt: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
            stillScrolling.notePointerMoved(to: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
        }
        expect(
            !stillScrolling.hoverHighlightArmed,
            "a wheel nudging the mouse a point per click stays disarmed for the whole gesture")
    }

    static func driftDoesNotRearm() {
        let state = armed()
        state.disarmHoverHighlight(pointerAt: rest)
        // The mouse-moved AppKit delivers as the gesture ends carries the pointer it already had.
        state.notePointerMoved(to: rest)
        expect(!state.hoverHighlightArmed, "the gesture's own trailing mouse-moved re-arms nothing")
        state.notePointerMoved(to: CGPoint(x: rest.x + 2, y: rest.y + 1))
        expect(!state.hoverHighlightArmed, "nor does a hand resting on the mouse jogging it a point")
        state.notePointerMoved(to: CGPoint(x: rest.x + 12, y: rest.y))
        expect(state.hoverHighlightArmed, "a real move afterwards brings the highlight back")
    }

    static func theDisarmTokenClearsLitRows() {
        let state = armed()
        let token = state.hoverDisarmToken
        state.disarmHoverHighlight(pointerAt: rest)
        expect(state.hoverDisarmToken != token, "disarming bumps the token that clears lit rows")

        let quiet = state.hoverDisarmToken
        state.disarmHoverHighlight(pointerAt: rest)
        state.notePointerMoved(to: rest)
        expect(
            state.hoverDisarmToken == quiet,
            "an already-disarmed palette bumps nothing, so a scroll re-renders no rows")

        state.notePointerMoved(to: CGPoint(x: rest.x + 40, y: rest.y))
        expect(
            state.hoverDisarmToken == quiet, "and arming is silent: pointer movement never rebuilds")
    }
}
