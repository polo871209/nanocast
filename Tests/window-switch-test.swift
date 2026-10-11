import Foundation

@main
@MainActor
struct WindowSwitchTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func entry(
        _ handle: Int, pid: Int32, app: String = "App", title: String = "Window"
    )
        -> WindowSwitchEntry
    {
        WindowSwitchEntry(
            handle: handle, windowID: UInt32(handle), pid: pid, appName: app, iconURL: nil,
            iconStamp: 0, title: title)
    }

    static func main() {
        label()
        ordering()
        initialSelection()
        chordOpensAndCommits()
        chordSteps()
        chordCancels()
        chordIgnoresOtherChords()
        chordFollowsTrigger()
        grid()

        print(failures == 0 ? "Window switch tests passed" : "\(failures) window switch tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func label() {
        expect(
            entry(0, pid: 1, app: "Safari", title: "Inbox").label == "Safari — Inbox",
            "a titled window reads as app, then title")
        expect(
            entry(0, pid: 1, app: "Preview", title: "  ").label == "Preview",
            "an untitled window reads as its app")
        expect(
            entry(0, pid: 1, app: "Notes", title: "Notes").label == "Notes",
            "a title that repeats the app name is not printed twice")
    }

    static func ordering() {
        let entries = [
            entry(0, pid: 10, app: "Zed"), entry(1, pid: 20, app: "Mail"),
            entry(2, pid: 20, app: "Mail"), entry(3, pid: 30, app: "Arc"),
            entry(4, pid: 40, app: "Books")
        ]
        let sorted = WindowSwitchOrder.sorted(entries, recency: [20, 10])
        expect(
            sorted.map(\.handle) == [1, 2, 0, 3, 4],
            "recent apps lead with their windows kept in sweep order, the rest follow by name")
        expect(
            WindowSwitchOrder.sorted(entries.reversed(), recency: [20, 10]).map(\.handle)
                == sorted.map(\.handle),
            "the order does not depend on the order apps were swept in")
    }

    static func initialSelection() {
        let entries = [entry(0, pid: 1), entry(1, pid: 1), entry(2, pid: 2)]
        expect(
            WindowSwitchOrder.initialSelection(in: entries, frontmost: 1, backward: false) == 2,
            "⌘Tab lands on the previous app, not on a sibling window")
        expect(
            WindowSwitchOrder.initialSelection(in: entries, frontmost: 1, backward: true) == 2,
            "⌘⇧Tab lands on the last window")
        expect(
            WindowSwitchOrder.initialSelection(in: Array(entries.prefix(2)), frontmost: 1, backward: false)
                == 1,
            "with one app running, ⌘Tab still moves off the current window")
        expect(
            WindowSwitchOrder.initialSelection(in: [entry(0, pid: 1)], frontmost: 1, backward: false) == 0,
            "a single window is the only choice")
    }

    static let command: UInt64 = 0x0010_0000
    static let shift: UInt64 = 0x0002_0000
    static let option: UInt64 = 0x0008_0000
    static let tab: Int64 = 48
    static let commandTab = WindowSwitchChord.Trigger(keyCode: Int(tab), modifiers: command)

    static func chordOpensAndCommits() {
        var chord = WindowSwitchChord(trigger: commandTab)
        let open = chord.handle(.keyDown(keyCode: tab, flags: command))
        expect(open == .init(swallows: true, action: .open(backward: false)), "⌘Tab opens")
        expect(chord.handle(.keyUp) == .init(swallows: true), "the Tab release is swallowed too")
        expect(
            chord.handle(.flagsChanged(flags: command | shift)) == .init(swallows: false),
            "a modifier change that keeps ⌘ passes through")
        let commit = chord.handle(.flagsChanged(flags: 0))
        expect(commit == .init(swallows: false, action: .commit), "releasing ⌘ commits")
        expect(!chord.isSwitching, "the commit ends the switch")
        expect(
            chord.handle(.keyDown(keyCode: 0, flags: command)) == .init(swallows: false),
            "after the switch other keys reach the app again")
    }

    static func chordSteps() {
        var chord = WindowSwitchChord(trigger: commandTab)
        let open = chord.handle(.keyDown(keyCode: tab, flags: command | shift))
        expect(open.action == .open(backward: true), "⌘⇧Tab opens backward")
        expect(chord.handle(.keyDown(keyCode: tab, flags: command)).action == .step(1), "Tab steps")
        expect(
            chord.handle(.keyDown(keyCode: tab, flags: command | shift)).action == .step(-1),
            "⇧Tab steps back")
        expect(chord.handle(.keyDown(keyCode: 123, flags: command)).action == .step(-1), "← steps back")
        expect(chord.handle(.keyDown(keyCode: 124, flags: command)).action == .step(1), "→ steps")
        expect(
            chord.handle(.keyDown(keyCode: 12, flags: command)) == .init(swallows: true),
            "⌘Q while switching never reaches the front app")
        expect(
            chord.handle(.keyDown(keyCode: 36, flags: command)).action == .commit, "Return commits")
    }

    static func chordCancels() {
        var chord = WindowSwitchChord(trigger: commandTab)
        _ = chord.handle(.keyDown(keyCode: tab, flags: command))
        expect(
            chord.handle(.keyDown(keyCode: 53, flags: command)) == .init(swallows: true, action: .cancel),
            "Escape cancels")
        expect(
            chord.handle(.flagsChanged(flags: 0)) == .init(swallows: false),
            "releasing ⌘ after a cancel switches nothing")
        _ = chord.handle(.keyDown(keyCode: tab, flags: command))
        chord.end()
        expect(
            chord.handle(.flagsChanged(flags: 0)).action == nil,
            "a switch the coordinator ended commits nothing on release")
    }

    static func chordIgnoresOtherChords() {
        var chord = WindowSwitchChord(trigger: commandTab)
        expect(
            chord.handle(.keyDown(keyCode: tab, flags: 0)) == .init(swallows: false),
            "a bare Tab is typing")
        expect(
            chord.handle(.keyDown(keyCode: tab, flags: command | 0x0004_0000)) == .init(swallows: false),
            "⌃⌘Tab belongs to someone else")
        expect(
            chord.handle(.keyDown(keyCode: tab, flags: command | 0x0008_0000)) == .init(swallows: false),
            "⌥⌘Tab belongs to someone else")
    }

    static func chordFollowsTrigger() {
        let optionTab = WindowSwitchChord.Trigger(keyCode: Int(tab), modifiers: option)
        var chord = WindowSwitchChord(trigger: optionTab)
        expect(
            chord.handle(.keyDown(keyCode: tab, flags: command)) == .init(swallows: false),
            "⌘Tab passes through when the trigger is ⌥Tab")
        expect(
            chord.handle(.keyDown(keyCode: tab, flags: option)).action == .open(backward: false),
            "the recorded chord opens the switcher")
        expect(
            chord.handle(.flagsChanged(flags: option | shift)).action == nil,
            "pressing ⇧ keeps the switch")
        expect(
            chord.handle(.flagsChanged(flags: 0)).action == .commit,
            "releasing the recorded modifier commits")

        let shiftTrigger = WindowSwitchChord.Trigger(keyCode: Int(tab), modifiers: command | shift)
        chord = WindowSwitchChord(trigger: shiftTrigger)
        expect(
            chord.handle(.keyDown(keyCode: tab, flags: command)) == .init(swallows: false),
            "a trigger with ⇧ needs ⇧")
        expect(
            chord.handle(.keyDown(keyCode: tab, flags: command | shift)).action
                == .open(backward: false),
            "a trigger with ⇧ opens forward")
        expect(
            chord.handle(.flagsChanged(flags: command)).action == nil,
            "releasing ⇧ alone keeps the switch")

        chord.trigger = nil
        expect(!chord.isSwitching, "changing the trigger ends the switch")
        expect(
            chord.handle(.keyDown(keyCode: tab, flags: command | shift)) == .init(swallows: false),
            "no trigger opens nothing")
    }

    static func grid() {
        let tile = CGSize(width: 100, height: 80)
        let wide = WindowSwitchGrid.fit(
            count: 3, tile: tile, gap: 10, padding: 10, bounds: CGSize(width: 1000, height: 1000),
            minimumScale: 0.5)
        expect(wide == WindowSwitchGrid(columns: 3, scale: 1), "a few tiles sit on one row at full size")
        let wrapped = WindowSwitchGrid.fit(
            count: 7, tile: tile, gap: 10, padding: 10, bounds: CGSize(width: 350, height: 1000),
            minimumScale: 0.5)
        expect(wrapped.columns == 3, "tiles wrap at the width that fits")
        let tall = WindowSwitchGrid.fit(
            count: 30, tile: tile, gap: 10, padding: 10, bounds: CGSize(width: 350, height: 300),
            minimumScale: 0.5)
        expect(tall.scale == 0.5, "overflowing rows shrink, but not below the floor")
        expect(
            WindowSwitchGrid.fit(
                count: 0, tile: tile, gap: 10, padding: 10, bounds: CGSize(width: 0, height: 0), minimumScale: 0.5)
                == WindowSwitchGrid(columns: 1, scale: 1),
            "an empty switcher still has a valid grid")
    }
}
