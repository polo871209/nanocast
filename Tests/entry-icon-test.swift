import AppKit
import Foundation

@main
@MainActor
struct EntryIconTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        } else {
            print("PASS  \(message)")
        }
    }

    static func everyCasePrintsDistinctly() {
        let icons: [EntryIcon] = [
            .file(stamp: 0),
            .file(stamp: 1),
            .symbol("star"),
            .symbol("bolt"),
            .contentType("public.png"),
            .contentType("public.jpeg")
        ]
        let printed = Set(icons.map { "\($0)" })
        expect(printed.count == icons.count, "each icon prints uniquely: \(printed.count)/\(icons.count)")
    }

    static func hashingSeparatesTheCases() {
        expect(EntryIcon.symbol("star") == EntryIcon.symbol("star"), "the same symbol is equal")
        expect(EntryIcon.symbol("star") != EntryIcon.symbol("bolt"), "two symbols differ")
        expect(
            EntryIcon.file(stamp: 0) != EntryIcon.file(stamp: 1),
            "one file at two stamps differs")
        expect(
            Set([EntryIcon.file(stamp: 0), .symbol("star"), .file(stamp: 0)]).count == 2,
            "hashing collapses only equal values")
    }

    static func everyCaseDraws() {
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let cases: [(String, EntryIcon)] = [
            ("file", .file(stamp: 0)),
            ("symbol", .symbol("star")),
            ("contentType", .contentType("public.png"))
        ]
        for (label, icon) in cases {
            let image = IconCache.icon(for: icon, fileURL: url)
            expect(image.size.width > 0, "\(label) draws something")
        }
    }

    static func askingTwiceIsStable() {
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let first = bitmap(IconCache.icon(for: .symbol("gear"), fileURL: url))
        let second = bitmap(IconCache.icon(for: .symbol("gear"), fileURL: url))
        expect(first != nil && first == second, "the same icon is stable across two asks")
    }

    static func cacheOnlyLookupMatchesTheDrawnIcon() {
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let cold = EntryIcon.symbol("nonexistent.glyph.\(UUID().uuidString)")
        expect(IconCache.cached(cold, fileURL: url) == nil, "a cold icon is not reported warm")

        let warm = EntryIcon.symbol("bookmark")
        _ = IconCache.icon(for: warm, fileURL: url)
        expect(IconCache.cached(warm, fileURL: url) != nil, "a drawn icon is reported warm")
    }

    static func aChangedIconRetiresTheCachedBitmap() {
        guard let bundle = makeBundle() else { return expect(false, "the fixture bundle writes") }
        defer { try? FileManager.default.removeItem(at: bundle) }

        let cold = FileIconStamp.value(for: bundle)
        expect(FileIconStamp.value(for: bundle) == cold, "an untouched bundle keeps its stamp")
        _ = IconCache.icon(for: .file(stamp: cold), fileURL: bundle)
        expect(
            IconCache.cached(.file(stamp: cold), fileURL: bundle) != nil, "the first decode is cached")

        try? Data([0]).write(to: URL(fileURLWithPath: bundle.path + "/Icon\r"))
        let warm = FileIconStamp.value(for: bundle)
        expect(warm != cold, "gaining a custom icon moves the stamp")
        expect(
            IconCache.cached(.file(stamp: warm), fileURL: bundle) == nil,
            "the moved stamp misses the bitmap decoded before the change")
    }

    static func bitmap(_ image: NSImage) -> Data? { image.tiffRepresentation }

    static func makeBundle() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("entry-icon-test-\(UUID().uuidString).app")
        guard
            (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true))
                != nil
        else { return nil }
        return url
    }

    static func main() {
        everyCasePrintsDistinctly()
        hashingSeparatesTheCases()
        everyCaseDraws()
        askingTwiceIsStable()
        cacheOnlyLookupMatchesTheDrawnIcon()
        aChangedIconRetiresTheCachedBitmap()

        print(failures == 0 ? "Entry icon tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
