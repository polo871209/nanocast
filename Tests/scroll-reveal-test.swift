import CoreGraphics
import Foundation

@main
@MainActor
struct SelectionRevealTests {
    static var failures = 0
    static var passes = 0

    static let band: CGFloat = 369
    static let rowHeight: CGFloat = 36

    static func expect(
        _ actual: SelectionReveal.Edge?, _ expected: SelectionReveal.Edge?, _ message: String
    ) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(String(describing: actual)), want \(expected as Any)")
        }
    }

    static func edge(rowTop top: CGFloat, height: CGFloat = rowHeight) -> SelectionReveal.Edge? {
        SelectionReveal.edge(rowTop: top, rowBottom: top + height, band: band)
    }

    static func main() {
        rowsInsideTheBandStayPut()
        rowsPastAnEdgeAlignToIt()
        theStripBehindTheBottomBar()
        aRowTallerThanTheBand()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func rowsInsideTheBandStayPut() {
        expect(edge(rowTop: 0), nil, "the first row at the band's top edge needs no scroll")
        expect(edge(rowTop: 180), nil, "nor does a row in the middle")
        expect(edge(rowTop: band - rowHeight), nil, "nor one flush with the bottom edge")
        expect(edge(rowTop: -0.3), nil, "a third of a point over the top edge is still inside")
        expect(edge(rowTop: band - rowHeight + 0.3), nil, "and so is a third of a point under")
    }

    static func rowsPastAnEdgeAlignToIt() {
        expect(edge(rowTop: -1), .top, "a row a point above the band aligns to the top")
        expect(edge(rowTop: -rowHeight), .top, "so does one scrolled a full row above it")
        expect(edge(rowTop: -4000), .top, "and one far above, after a jump to the list's start")
        expect(edge(rowTop: band - rowHeight + 1), .bottom, "a row a point below aligns to the bottom")
        expect(edge(rowTop: band + 4000), .bottom, "and so does one far below it")
    }

    static func theStripBehindTheBottomBar() {
        expect(edge(rowTop: 369), .bottom, "the row that lands in the strip is moved into the band")
        expect(edge(rowTop: 333), nil, "while the row flush above the strip is left alone")
    }

    static func aRowTallerThanTheBand() {
        expect(edge(rowTop: 0, height: band + 100), nil, "a too-tall row pinned at the top is settled")
        expect(edge(rowTop: -50, height: band + 100), .top, "one scrolled past its top is pulled back")
        expect(edge(rowTop: 20, height: band + 100), .top, "and one hanging below the top is too")
    }
}
