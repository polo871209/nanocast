import CoreGraphics
import Foundation

@main
@MainActor
struct CalloutPlacementTests {
    static var failures = 0
    static var passes = 0

    static let size = Theme.Size.shortcutPopover
    static let gap = Theme.Spacing.sm
    static let inset = Theme.Spacing.xs
    static let cornerRadius = Theme.Radius.menuPanel
    static let caretWidth = Theme.Size.calloutCaretWidth

    static let fieldInsetFromPaneEdge =
        Theme.Spacing.xxl + Theme.Spacing.xl + Theme.Size.shortcutRecorder / 2
    static var caretLimit: CGFloat { cornerRadius + caretWidth / 2 }

    static func resolve(field: CGRect, container: CGSize) -> CalloutPlacement {
        CalloutPlacement.resolve(
            field: field, container: container, size: size, gap: gap, inset: inset,
            cornerRadius: cornerRadius, caretWidth: caretWidth)
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        expect(abs(actual - expected) < 0.001, "\(message) — got \(actual), want \(expected)")
    }

    static func main() {
        centredOnARealRow()
        flipping()
        horizontalClamping()
        caretTracking()
        degenerateContainers()
        rowGrammar()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func centredOnARealRow() {
        for paneWidth in [Theme.Size.settingsSidebar + 320, 720, 1100] as [CGFloat] {
            let field = CGRect(
                x: paneWidth - fieldInsetFromPaneEdge - Theme.Size.shortcutRecorder / 2,
                y: 400, width: Theme.Size.shortcutRecorder, height: 24)
            let placement = resolve(field: field, container: CGSize(width: paneWidth, height: 800))

            expect(
                placement.center.x, field.midX,
                "pane \(Int(paneWidth)): the callout centres on the recorder")
            expect(
                placement.caretX, size.width / 2,
                "pane \(Int(paneWidth)): the caret sits dead centre")
        }

        expect(
            size.width / 2 + inset <= fieldInsetFromPaneEdge,
            "the callout is narrow enough to centre on a trailing-edge recorder — widen it and the caret skews"
        )
    }

    static func flipping() {
        let container = CGSize(width: 600, height: 800)
        let roomy = CGRect(x: 400, y: 400, width: 80, height: 24)
        let above = resolve(field: roomy, container: container)
        expect(above.caretEdge == .bottom, "a field with room above gets the callout above it")
        expect(
            above.center.y, roomy.minY - gap - size.height / 2,
            "the callout's bottom edge sits one gap above the field")

        expect(
            above.center.y + size.height / 2 <= roomy.minY,
            "the callout never overlaps the field it points at")

        let tight = CGRect(x: 400, y: 40, width: 80, height: 24)
        let below = resolve(field: tight, container: container)
        expect(below.caretEdge == .top, "a field near the pane's top flips the callout below it")
        expect(
            below.center.y, tight.maxY + gap + size.height / 2,
            "the flipped callout's top edge sits one gap below the field")

        let exact = CGRect(x: 400, y: size.height + gap, width: 80, height: 24)
        expect(
            resolve(field: exact, container: container).caretEdge == .bottom,
            "a field with exactly enough room above does not flip")
        let onePointShort = CGRect(x: 400, y: size.height + gap - 1, width: 80, height: 24)
        expect(
            resolve(field: onePointShort, container: container).caretEdge == .top,
            "one point short of the room it needs does flip")
    }

    static func horizontalClamping() {
        let container = CGSize(width: 600, height: 800)

        let centered = resolve(
            field: CGRect(x: 260, y: 400, width: 80, height: 24), container: container)
        expect(centered.center.x, 300, "a field mid-pane centres the callout on it")

        let trailing = resolve(
            field: CGRect(x: 500, y: 400, width: 80, height: 24), container: container)
        expect(
            trailing.center.x, container.width - size.width / 2 - inset,
            "a trailing-edge field slides the callout back inside the pane")
        expect(
            trailing.center.x + size.width / 2 <= container.width - inset + 0.001,
            "the clamped callout keeps its inset from the trailing edge")

        let leading = resolve(
            field: CGRect(x: 0, y: 400, width: 80, height: 24), container: container)
        expect(leading.center.x, size.width / 2 + inset, "a leading-edge field clamps the same way")
        expect(
            leading.center.x - size.width / 2 >= inset - 0.001,
            "the clamped callout keeps its inset from the leading edge")
    }

    static func caretTracking() {
        let container = CGSize(width: 600, height: 800)

        let centered = resolve(
            field: CGRect(x: 260, y: 400, width: 80, height: 24), container: container)
        expect(centered.caretX, size.width / 2, "an unclamped callout points from its middle")

        let trailing = CGRect(x: 500, y: 400, width: 80, height: 24)
        let clamped = resolve(field: trailing, container: container)
        expect(
            clamped.center.x - size.width / 2 + clamped.caretX, trailing.midX,
            "the pointer still lands on the field's centre after the body is clamped")
        expect(clamped.caretX > size.width / 2, "and it does that by sitting past the middle")

        let extreme = resolve(
            field: CGRect(x: 596, y: 400, width: 80, height: 24), container: container)
        expect(
            extreme.caretX <= size.width - caretLimit + 0.001,
            "the pointer stops clear of the trailing corner arc")
        let farLeading = resolve(
            field: CGRect(x: -200, y: 400, width: 80, height: 24), container: container)
        expect(
            farLeading.caretX >= caretLimit - 0.001,
            "the pointer stops clear of the leading corner arc")
    }

    static func rowGrammar() {
        expect(
            Theme.Size.checkbox <= Theme.Size.rowIcon,
            "the uninstall checkbox fits inside the shared leading slot")
        expect(Theme.Size.checkbox > 0, "and is a real size")
    }

    static func degenerateContainers() {
        let narrow = resolve(
            field: CGRect(x: 10, y: 400, width: 80, height: 24),
            container: CGSize(width: 200, height: 800))
        expect(narrow.center.x, size.width / 2 + inset, "a too-narrow pane still resolves finitely")
        expect(narrow.caretX.isFinite, "and its pointer stays a real number")

        let short = resolve(
            field: CGRect(x: 100, y: 4, width: 80, height: 24),
            container: CGSize(width: 600, height: 60))
        expect(short.caretEdge == .top, "a pane with no room above flips below even when cramped")
        expect(short.center.y.isFinite, "and still resolves finitely")
    }
}
