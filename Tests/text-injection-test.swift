import AppKit
import Foundation

@main
@MainActor
struct TextInjectionTests {
    static var failures = 0
    static var passes = 0

    static func main() async {
        _ = NSApplication.shared
        await testDeliveryQueue()
        testDeliveryCompletion()
        testReplacementPolicy()
        testUnicodeChunks()
        testPasteboardLease()
        testOwnEditorInjection()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testDeliveryQueue() async {
        let queue = DeliveryQueue()
        var order: [String] = []
        queue.enqueue {
            order.append("first-start")
            try? await Task.sleep(for: .milliseconds(30))
            order.append("first-end")
        }
        queue.enqueue {
            order.append("second")
        }
        await queue.drain()
        check(
            "deliveries are retained and serialized",
            order == ["first-start", "first-end", "second"] && queue.isIdle)

        var cancelledRan = false
        queue.enqueue {
            try? await Task.sleep(for: .milliseconds(30))
        }
        queue.enqueue {
            cancelledRan = true
        }
        queue.cancelAll()
        try? await Task.sleep(for: .milliseconds(60))
        check("cancelling the queue drops a delivery that has not started", !cancelledRan && queue.isIdle)
    }

    private static func testDeliveryCompletion() {
        var completionCount = 0
        var failureCount = 0
        let completion = DeliveryCompletion(
            onDelivered: { completionCount += 1 }, onFailed: { failureCount += 1 })
        completion.confirm()
        completion.confirm()
        completion.settle()
        check(
            "delivery completion invokes its callback exactly once after confirmation",
            completion.isConfirmed && completionCount == 1 && failureCount == 0)

        var unconfirmedFailures = 0
        let unconfirmed = DeliveryCompletion(onFailed: { unconfirmedFailures += 1 })
        unconfirmed.settle()
        unconfirmed.settle()
        unconfirmed.confirm()
        check(
            "a delivery that returned early reports failure exactly once and stays unconfirmed",
            !unconfirmed.isConfirmed && unconfirmedFailures == 1)
    }

    private static func testReplacementPolicy() {
        check(
            "unavailable AX text attributes use the event delivery path",
            AccessibilityReplacement.unavailable.fallsBackToEvents)
        check(
            "a rejected AX replacement fails closed instead of typing by events",
            !AccessibilityReplacement.rejected.fallsBackToEvents)
        check(
            "AX replacement confirmation requires the observable text to actually change",
            TextReplacementPolicy.confirmsReplacement(
                originalValue: "draft",
                replacementRange: NSRange(location: 0, length: 5),
                insertedText: "PROBE_OK",
                observedValue: "PROBE_OK"))
        check(
            "an AX setter success with unchanged text is not accepted as delivery",
            !TextReplacementPolicy.confirmsReplacement(
                originalValue: "draft",
                replacementRange: NSRange(location: 0, length: 5),
                insertedText: "PROBE_OK",
                observedValue: "draft"))
        check(
            "an AX write that lands somewhere unexpected is not accepted as delivery",
            !TextReplacementPolicy.confirmsReplacement(
                originalValue: "keep draft",
                replacementRange: NSRange(location: 5, length: 5),
                insertedText: "PROBE_OK",
                observedValue: "PROBE_OK draft"))
        check(
            "an unreadable value after the write is not accepted as delivery",
            !TextReplacementPolicy.confirmsReplacement(
                originalValue: "draft",
                replacementRange: NSRange(location: 0, length: 5),
                insertedText: "PROBE_OK",
                observedValue: nil))
        check(
            "unreadable AX state accepts a posted paste after the conservative delay",
            PasteConfirmationPolicy.acceptsUnconfirmedDelivery(
                attempt: 15, hadPreviousState: true, readStateAfterPaste: false))
        check(
            "readable unchanged AX state is not treated as a confirmed paste",
            !PasteConfirmationPolicy.acceptsUnconfirmedDelivery(
                attempt: 79, hadPreviousState: true, readStateAfterPaste: true))
    }

    private static func testUnicodeChunks() {
        check(
            "a Unicode keystroke never carries more than Blink's four-unit cap",
            UnicodeTypingChunk.split(String(repeating: "a", count: 30))
                .allSatisfy { $0.count <= UnicodeTypingChunk.maxUTF16Units })
        check(
            "chunked Unicode keystrokes reassemble into the original text",
            UnicodeTypingChunk.split("Fix this sentence, 雪が降る 👨‍👩‍👧 — done.")
                .flatMap { $0 } == Array("Fix this sentence, 雪が降る 👨‍👩‍👧 — done.".utf16))
        check(
            "a surrogate pair is never split across two keystrokes",
            UnicodeTypingChunk.split("ab👩🏽‍🚀").allSatisfy { chunk in
                String(decoding: chunk, as: UTF16.self).unicodeScalars.allSatisfy { $0.value != 0xFFFD }
            })
        check("empty text produces no keystrokes", UnicodeTypingChunk.split("").isEmpty)
    }

    private static func testPasteboardLease() {
        let backingPasteboard = NSPasteboard(
            name: .init("nanocast-text-injection-tests-\(UUID().uuidString)"))
        let pasteboard = StubPasteboard(backing: backingPasteboard)
        defer { backingPasteboard.releaseGlobally() }
        let customType = NSPasteboard.PasteboardType("com.example.custom")
        let firstItem = NSPasteboardItem()
        firstItem.setString("Original", forType: .string)
        firstItem.setData(Data([0, 1, 2, 3]), forType: customType)
        let secondType = NSPasteboard.PasteboardType("com.example.second")
        let secondItem = NSPasteboardItem()
        secondItem.setData(Data([4, 5, 6]), forType: secondType)
        check(
            "pasteboard fixture writes multiple items and types",
            pasteboard.replaceObjects([firstItem, secondItem]))

        let lease = TemporaryPasteboardLease.begin(text: "Temporary", pasteboard: pasteboard)
        check(
            "the lent pasteboard carries the text and no representation of the original",
            lease?.isOwned == true
                && pasteboard.string(forType: .string) == "Temporary"
                && pasteboard.pasteboardItems?.count == 1
                && pasteboard.pasteboardItems?[0].data(forType: customType) == nil
                && pasteboard.pasteboardItems?[0].data(forType: secondType) == nil)
        let restoreResult = lease?.restoreIfOwned()
        let restoredItems = pasteboard.pasteboardItems
        check(
            "pasteboard restoration preserves every item, type, and payload",
            restoreResult != nil
                && restoredItems?.count == 2
                && restoredItems?[0].string(forType: .string) == "Original"
                && restoredItems?[0].data(forType: customType) == Data([0, 1, 2, 3])
                && restoredItems?[1].data(forType: secondType) == Data([4, 5, 6]))
        check(
            "pasteboard restoration leaves no Nanocast marker on the restored clipboard",
            restoredItems?.allSatisfy { !$0.types.contains(ClipboardManager.internalType) } == true)

        pasteboard.writeFailuresRemaining = 1
        var recoveredMutationCount: Int?
        let failedLease = TemporaryPasteboardLease.begin(
            text: "Temporary failure", pasteboard: pasteboard,
            onMutation: { recoveredMutationCount = $0 })
        check(
            "a failed temporary write restores the original clipboard before falling back",
            failedLease == nil
                && pasteboard.string(forType: .string) == "Original"
                && pasteboard.pasteboardItems?.count == 2
                && recoveredMutationCount == pasteboard.changeCount)

        let supersededLease = TemporaryPasteboardLease.begin(
            text: "Temporary again", pasteboard: pasteboard)
        let newerItem = NSPasteboardItem()
        newerItem.setString("Newer copy", forType: .string)
        _ = pasteboard.replaceObjects([newerItem])
        check(
            "pasteboard restoration never overwrites a newer copy",
            supersededLease?.restoreIfOwned() == .superseded
                && pasteboard.string(forType: .string) == "Newer copy")

        _ = pasteboard.replaceObjects([])
        let emptyLease = TemporaryPasteboardLease.begin(
            text: "Temporary from empty", pasteboard: pasteboard)
        check(
            "an empty clipboard still lends a temporary string to paste",
            emptyLease?.isOwned == true
                && pasteboard.string(forType: .string) == "Temporary from empty")
        check(
            "restoring a borrowed empty clipboard leaves it empty again",
            emptyLease?.restoreIfOwned() != nil && pasteboard.pasteboardItems?.isEmpty != false)

        let imageOnlyItem = NSPasteboardItem()
        imageOnlyItem.setData(Data([9, 8, 7]), forType: .png)
        _ = pasteboard.replaceObjects([imageOnlyItem])
        let imageLease = TemporaryPasteboardLease.begin(
            text: "Temporary over image", pasteboard: pasteboard)
        check(
            "a non-text clipboard still lends a temporary string to paste",
            imageLease?.isOwned == true
                && pasteboard.string(forType: .string) == "Temporary over image")
        check(
            "restoring a borrowed image clipboard returns the original payload",
            imageLease?.restoreIfOwned() != nil
                && pasteboard.pasteboardItems?.count == 1
                && pasteboard.data(forType: .png) == Data([9, 8, 7])
                && pasteboard.string(forType: .string) == nil)
    }

    private static func testOwnEditorInjection() {
        let editor = HarnessEditor(frame: NSRect(x: 0, y: 0, width: 320, height: 120))

        editor.string = "Regards, name"
        editor.inject("Ada Lovelace", over: NSRange(location: 9, length: 4))
        check("the range is replaced in place", editor.string == "Regards, Ada Lovelace")
        check(
            "the caret lands after the inserted text",
            editor.selectedRange() == NSRange(location: 21, length: 0))

        editor.string = "flag "
        editor.inject("\u{1F1F3}\u{1F1F1}", over: NSRange(location: 5, length: 0))
        check(
            "the caret counts UTF-16 units, not characters",
            editor.selectedRange() == NSRange(location: 9, length: 0))
    }

    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
            passes += 1
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }
}

@MainActor
private final class StubPasteboard: PasteboardAccess {
    let backing: NSPasteboard
    var writeFailuresRemaining = 0

    init(backing: NSPasteboard) {
        self.backing = backing
    }

    var changeCount: Int { backing.changeCount }
    var pasteboardItems: [NSPasteboardItem]? { backing.pasteboardItems }

    @discardableResult
    func clearContents() -> Int {
        backing.clearContents()
    }

    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        if writeFailuresRemaining > 0 {
            writeFailuresRemaining -= 1
            return false
        }
        return backing.writeObjects(objects)
    }

    func replaceObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        clearContents()
        return objects.isEmpty || writeObjects(objects)
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        backing.string(forType: type)
    }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        backing.data(forType: type)
    }
}

@MainActor
final class ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.nanocast.internal")
    func prepareForNanocastPasteboardMutation() {}
    func synchronizeAfterNanocastPasteboardMutation(changeCount: Int) {}
}

enum Permissions {
    static func ensureAccessibility() -> Bool { false }
    static func isAccessibilityTrusted() -> Bool { false }
}

enum Paster {
    static let nanocastEventTag: Int64 = 0x54494E59
    @MainActor static func postCommandV(toPid pid: pid_t? = nil) {}
}

private final class HarnessEditor: NSTextView, InjectableTextView {}
