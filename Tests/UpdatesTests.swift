import Foundation
import Security

@main
@MainActor
struct UpdatesTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        parsesVersions()
        ordersVersions()
        roundTripsVersionsThroughJSON()
        derivesChannels()
        picksNewestForChannel()
        rejectsUnusableFeeds()
        offersOnlyWhatIsWorthInstalling()
        refusesWhatTheRunningIdentityDoesNotVouchFor()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func parsesVersions() {
        expect(AppVersion("0.2.1")?.description == "0.2.1", "parses a plain triple")
        expect(AppVersion("v0.2.1")?.description == "0.2.1", "strips the tag's leading v")
        expect(AppVersion(" 0.2.1 ")?.description == "0.2.1", "tolerates surrounding whitespace")
        expect(AppVersion("v0.11.21-3")?.description == "0.11.21-3", "parses the Nanocast revision")

        expect(AppVersion("0.2") == nil, "rejects a two-part version")
        expect(AppVersion("0.2.1.3") == nil, "rejects a four-part version")
        expect(AppVersion("0.2.x") == nil, "rejects a non-numeric field")
        expect(AppVersion("0.2.-1") == nil, "rejects a signed field")
        expect(AppVersion("0.2.0-beta.1") == nil, "rejects a prerelease suffix")
        expect(AppVersion("0.2.0-rc") == nil, "rejects any suffix")
        expect(AppVersion("0.2.0-") == nil, "rejects an empty revision")
        expect(AppVersion("0.2.0-1-2") == nil, "rejects a second revision")
        expect(AppVersion("") == nil, "rejects an empty string")
        expect(AppVersion("nightly") == nil, "rejects a name")
    }

    static func ordersVersions() {
        func version(_ text: String) -> AppVersion {
            guard let parsed = AppVersion(text) else {
                fatalError("the ordering cases must all parse — \(text) did not")
            }
            return parsed
        }

        expect(version("1.10.0") > version("1.9.0"), "compares minor numerically, not lexically")
        expect(version("2.0.0") > version("1.99.99"), "major outranks everything below it")
        expect(version("0.2.1") > version("0.2.0"), "patch breaks a tie")
        expect(version("0.2.10") > version("0.2.9"), "compares patch numerically, not lexically")
        expect(version("0.2.1") == version("0.2.1"), "equal triples are equal")
        expect(version("0.11.21-2") > version("0.11.21-1"), "the revision breaks a tie")
        expect(version("0.11.21-10") > version("0.11.21-9"), "compares the revision numerically")
        expect(version("0.11.22-1") > version("0.11.21-9"), "a newer Tinycast base outranks any revision")
        expect(version("0.11.21-1") > version("0.11.21"), "a revision outranks its bare base")
    }

    static func roundTripsVersionsThroughJSON() {
        guard let original = AppVersion("0.2.7"),
            let encoded = try? JSONEncoder().encode(original),
            let decoded = try? JSONDecoder().decode(AppVersion.self, from: encoded)
        else {
            failures += 1
            print("FAIL: a version survives the cache file")
            return
        }
        expect(decoded == original, "a version survives the cache file")
        expect(
            String(bytes: encoded, encoding: .utf8) == "\"0.2.7\"",
            "and is stored as a readable string rather than a field bag")
        expect(
            (try? JSONDecoder().decode(AppVersion.self, from: Data("\"junk\"".utf8))) == nil,
            "a corrupt cached version fails to decode instead of defaulting")
    }

    static func derivesChannels() {
        let stable = ReleaseChannel(bundleID: "com.nanocast.app")
        let dev = ReleaseChannel(bundleID: "com.nanocast.app.dev")

        expect(stable == .stable, "the shipped bundle id is the stable channel")
        expect(dev == .development, "the dev bundle id is a local build")
        expect(
            ReleaseChannel(bundleID: "com.nanocast.app.beta") == .development,
            "a retired beta bundle id never updates")
        expect(ReleaseChannel(bundleID: nil) == .development, "a missing bundle id never updates")

        expect(stable.updatesItself, "the shipped app updates itself")
        expect(!dev.updatesItself, "a local build does not update itself")

        expect(stable.accepts(prerelease: false), "stable takes releases")
        expect(!stable.accepts(prerelease: true), "stable never takes a prerelease")
        expect(
            !dev.accepts(prerelease: true) && !dev.accepts(prerelease: false),
            "a local build accepts nothing at all")
    }

    /// Shaped like GitHub's `/releases` payload, down to the snake-cased keys.
    static func feed(_ entries: String...) -> Data {
        Data("[\(entries.joined(separator: ","))]".utf8)
    }

    static func entry(
        tag: String, prerelease: Bool, draft: Bool = false, assets: [String] = ["Nanocast-x.zip"]
    ) -> String {
        let list = assets.map {
            """
            {"name":"\($0)","size":1024,
             "browser_download_url":"https://example.invalid/\($0)"}
            """
        }
        return """
            {"tag_name":"\(tag)","prerelease":\(prerelease),"draft":\(draft),
             "published_at":"2026-01-05T12:00:00Z",
             "assets":[\(list.joined(separator: ","))]}
            """
    }

    static func picksNewestForChannel() {
        let body = feed(
            entry(tag: "v0.2.0", prerelease: false),
            entry(tag: "v0.3.0", prerelease: false),
            entry(tag: "v0.4.0", prerelease: true))

        let stable = ReleaseFeed.newest(from: body, channel: .stable)
        expect(stable?.version == AppVersion("0.3.0"), "stable takes the newest release")
        expect(stable?.tag == "v0.3.0", "and keeps the tag as published")
        expect(stable?.assetSize == 1024, "and the asset size, for the progress readout")
        expect(
            stable?.assetURL.absoluteString.hasSuffix(".zip") == true,
            "and selects the zip asset")
        expect(stable?.publishedAt != nil, "and parses the ISO-8601 timestamp")

        expect(
            ReleaseFeed.newest(from: body, channel: .development) == nil,
            "a local build is offered nothing, however new the feed is")
    }

    static func rejectsUnusableFeeds() {
        expect(
            ReleaseFeed.newest(from: Data(), channel: .stable) == nil,
            "an empty body yields nil")
        expect(
            ReleaseFeed.newest(
                from: Data("not json".utf8), channel: .stable) == nil,
            "a malformed body yields nil rather than throwing")
        expect(
            ReleaseFeed.newest(from: feed(), channel: .stable) == nil,
            "an empty feed yields nil")

        expect(
            ReleaseFeed.newest(
                from: feed(entry(tag: "v0.3.0", prerelease: false, draft: true)), channel: .stable) == nil,
            "a draft is not installable")
        expect(
            ReleaseFeed.newest(
                from: feed(entry(tag: "v0.3.0", prerelease: false, assets: [])), channel: .stable) == nil,
            "a release with no assets is skipped")
        expect(
            ReleaseFeed.newest(
                from: feed(entry(tag: "v0.3.0", prerelease: false, assets: ["Nanocast-x.dmg"])),
                channel: .stable) == nil,
            "a DMG-only release is not installable, so it is not offered")
        expect(
            ReleaseFeed.newest(
                from: feed(entry(tag: "nightly", prerelease: false)), channel: .stable) == nil,
            "an unparseable tag is skipped")
        expect(
            ReleaseFeed.newest(
                from: feed(entry(tag: "v0.3.0-beta.1", prerelease: false)), channel: .stable) == nil,
            "a prerelease-shaped tag is skipped even when flagged as a release")

        let mixed = feed(
            entry(tag: "v0.3.0", prerelease: false), entry(tag: "junk", prerelease: false))
        expect(
            ReleaseFeed.newest(from: mixed, channel: .stable)?.version
                == AppVersion("0.3.0"),
            "one bad entry does not discard the whole feed")
    }

    static func offersOnlyWhatIsWorthInstalling() {
        let running = AppVersion("0.2.0")!
        let newer = AvailableRelease(
            version: AppVersion("0.3.0")!, tag: "v0.3.0",
            assetURL: URL(string: "https://example.invalid/a.zip")!, assetSize: 1,
            publishedAt: nil)
        let same = AvailableRelease(
            version: running, tag: "v0.2.0",
            assetURL: URL(string: "https://example.invalid/a.zip")!, assetSize: 1,
            publishedAt: nil)

        expect(
            ReleaseFeed.offer(newer, running: running)?.version == newer.version,
            "a newer release is offered")
        expect(
            ReleaseFeed.offer(same, running: running) == nil,
            "the running version is not an update")
        expect(
            ReleaseFeed.offer(nil, running: running) == nil,
            "nothing in the feed offers nothing")
        expect(
            ReleaseFeed.offer(newer, running: AppVersion("0.4.0")!) == nil,
            "an older release never downgrades a newer install")
    }

    static func refusesWhatTheRunningIdentityDoesNotVouchFor() {
        expect(
            BundleSignature.trustedHash(of: URL(fileURLWithPath: "/System/Applications/Calculator.app"))
                == nil,
            "a bundle signed by another identity is refused")
        expect(
            BundleSignature.trustedHash(of: URL(fileURLWithPath: "/nonexistent.app")) == nil,
            "nothing is trusted without a seal to check")
    }
}
