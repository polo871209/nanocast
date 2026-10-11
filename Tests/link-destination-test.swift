import Foundation

@main
@MainActor
struct LinkDestinationTests {
    static var failures = 0
    static var passes = 0

    static let home = "/Users/nanocast-harness"

    static func main() {
        destinationDetection()
        pathDetection()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func destinationDetection() {
        expect(detect("https://example.com") == .web(url("https://example.com")), "https is a website")
        expect(detect("http://example.com/a") == .web(url("http://example.com/a")), "http is a website")
        expect(
            detect("example.com/search?q=1") == .web(url("https://example.com/search?q=1")),
            "a bare host gains https, keeping its path and query")
        expect(
            detect("sub.example.co.uk") == .web(url("https://sub.example.co.uk")),
            "a multi-label host is still a website")
        expect(
            detect("example.com:8080/x") == .web(url("https://example.com:8080/x")),
            "a port does not stop a bare host being a website")
        expect(
            detect("spotify://track/1") == .deeplink(url("spotify://track/1")),
            "an unknown scheme is a deeplink")
        expect(
            detect("shortcuts://run-shortcut?name=Focus")
                == .deeplink(url("shortcuts://run-shortcut?name=Focus")),
            "a deeplink keeps its query")
        expect(
            detect("mailto:someone@example.com") == .deeplink(url("mailto:someone@example.com")),
            "a schemeless-authority scheme is still a deeplink")
        expect(
            detect("smb://server/share") == .network(url("smb://server/share")),
            "smb is a network path")
        expect(
            detect("afp://server/share") == .network(url("afp://server/share")),
            "afp is a network path")
        expect(
            detect("http://example.com/a b") == .web(url("http://example.com/a%20b")),
            "a literal space is rescued rather than rejected")
        expect(
            detect("https://example.com/a%20b") == .web(url("https://example.com/a%20b")),
            "an already-encoded value is not encoded twice")

        expect(detect("") == nil, "an empty link resolves to nothing")
        expect(detect("   ") == nil, "a whitespace-only link resolves to nothing")
        expect(detect("not a url") == nil, "prose is not a destination")
        expect(detect("{argument}") == nil, "a bare leftover placeholder is not a destination")
        expect(detect("1.5") == nil, "a decimal is not a host")
        expect(detect("C:/Users/x") == nil, "a drive letter is not a scheme")
    }

    static func pathDetection() {
        expect(detect("/tmp") == .path("/tmp"), "an absolute path is a path")
        expect(
            detect("~/Downloads") == .path("\(home)/Downloads"),
            "a tilde expands against the injected home")
        expect(detect("~") == .path(home), "a bare tilde is the home directory")
        expect(
            detect("  ~/Projects/Nanocast  ") == .path("\(home)/Projects/Nanocast"),
            "surrounding whitespace is trimmed before detection")
        expect(
            detect("file:///Users/x/notes.md") == .path("/Users/x/notes.md"),
            "a file URL resolves to the path it names, not to a deeplink")
        expect(
            LinkDestination.detect("~/Downloads", homeDirectory: "/Users/other/")
                == .path("/Users/other/Downloads"),
            "a trailing slash on the home directory does not double up")
    }

    static func detect(_ value: String) -> LinkDestination? {
        LinkDestination.detect(value, homeDirectory: home)
    }

    static func url(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            fail("harness could not build \(value)")
            exit(1)
        }
        return url
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
