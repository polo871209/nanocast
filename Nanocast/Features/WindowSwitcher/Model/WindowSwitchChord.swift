import Foundation

struct WindowSwitchChord: Sendable {
    struct Trigger: Equatable, Sendable {
        let keyCode: Int64
        let modifiers: UInt64

        init(keyCode: Int, modifiers: UInt64) {
            self.keyCode = Int64(keyCode)
            self.modifiers = modifiers & Flag.all
        }

        fileprivate var holdModifiers: UInt64 { modifiers & ~Flag.shift }
        fileprivate var shiftSteps: Bool { modifiers & Flag.shift == 0 }
    }

    enum Input: Sendable {
        case keyDown(keyCode: Int64, flags: UInt64)
        case keyUp
        case flagsChanged(flags: UInt64)
    }

    enum Action: Equatable, Sendable {
        case open(backward: Bool)
        case step(Int)
        case commit
        case cancel
    }

    struct Outcome: Equatable, Sendable {
        var swallows: Bool
        var action: Action?
    }

    private enum KeyCode {
        static let escape: Int64 = 53
        static let returnKey: Int64 = 36
        static let keypadEnter: Int64 = 76
        static let leftArrow: Int64 = 123
        static let rightArrow: Int64 = 124
    }

    fileprivate enum Flag {
        static let shift: UInt64 = 0x0002_0000
        static let control: UInt64 = 0x0004_0000
        static let option: UInt64 = 0x0008_0000
        static let command: UInt64 = 0x0010_0000
        static let all = shift | control | option | command
    }

    var trigger: Trigger? {
        didSet { isSwitching = false }
    }
    private(set) var isSwitching = false

    init(trigger: Trigger?) {
        self.trigger = trigger
    }

    mutating func end() {
        isSwitching = false
    }

    mutating func handle(_ input: Input) -> Outcome {
        switch input {
        case .keyDown(let keyCode, let flags):
            return keyDown(keyCode, flags: flags)
        case .keyUp:
            return Outcome(swallows: isSwitching)
        case .flagsChanged(let flags):
            guard isSwitching, let trigger, flags & trigger.holdModifiers != trigger.holdModifiers
            else { return Outcome(swallows: false) }
            isSwitching = false
            return Outcome(swallows: false, action: .commit)
        }
    }

    private mutating func keyDown(_ keyCode: Int64, flags: UInt64) -> Outcome {
        if let trigger, keyCode == trigger.keyCode {
            let held = flags & Flag.all
            let backward = trigger.shiftSteps && held & Flag.shift != 0
            let chord = trigger.shiftSteps ? held & ~Flag.shift : held
            guard chord == trigger.modifiers else { return switchingKey(keyCode) }
            defer { isSwitching = true }
            return Outcome(
                swallows: true,
                action: isSwitching ? .step(backward ? -1 : 1) : .open(backward: backward))
        }
        return switchingKey(keyCode)
    }

    private mutating func switchingKey(_ keyCode: Int64) -> Outcome {
        guard isSwitching else { return Outcome(swallows: false) }
        switch keyCode {
        case KeyCode.escape:
            isSwitching = false
            return Outcome(swallows: true, action: .cancel)
        case KeyCode.returnKey, KeyCode.keypadEnter:
            isSwitching = false
            return Outcome(swallows: true, action: .commit)
        case KeyCode.leftArrow:
            return Outcome(swallows: true, action: .step(-1))
        case KeyCode.rightArrow:
            return Outcome(swallows: true, action: .step(1))
        default:
            return Outcome(swallows: true)
        }
    }
}
