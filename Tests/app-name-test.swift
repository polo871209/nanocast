import Foundation

@main
struct AppNameTest {
    static func main() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("nanocast-app-name-\(UUID().uuidString)")

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        func makeApp(_ fileName: String, info: [String: Any]) -> Bundle? {
            let url = root.appendingPathComponent(fileName)
            let contents = url.appendingPathComponent("Contents")
            try? fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try? PropertyListSerialization.data(
                fromPropertyList: info, format: .xml, options: 0)
            try? data?.write(to: contents.appendingPathComponent("Info.plist"))
            return Bundle(url: url)
        }

        check(
            "a blank display name is not a name",
            AppDisplayName.named("") == nil && AppDisplayName.named("   ") == nil
                && AppDisplayName.named("\n\t") == nil)
        check("a missing value is not a name", AppDisplayName.named(nil) == nil)
        check("a non-string value is not a name", AppDisplayName.named(42) == nil)
        check("a name is trimmed", AppDisplayName.named("  Paw  ") == "Paw")

        check(
            "a blank display name falls back to CFBundleName",
            AppDisplayName.inInfo(["CFBundleDisplayName": "", "CFBundleName": "RapidAPI"])
                == "RapidAPI")
        check(
            "a present display name still wins",
            AppDisplayName.inInfo(["CFBundleDisplayName": "Shown", "CFBundleName": "Internal"])
                == "Shown")
        check(
            "an info dictionary naming nothing yields nil",
            AppDisplayName.inInfo(["CFBundleDisplayName": " ", "CFBundleName": ""]) == nil)
        // Image Playground's loctable ships both, and CFBundle reads the platform-suffixed one.
        check(
            "the macOS variant of a key wins over the bare key",
            AppDisplayName.inInfo([
                "CFBundleDisplayName-macos": "Image Playground",
                "CFBundleDisplayName": "Playground", "CFBundleName": "Image Playground"
            ]) == "Image Playground")
        check(
            "a blank macOS variant falls through to the bare key",
            AppDisplayName.inInfo([
                "CFBundleDisplayName-macos": "", "CFBundleDisplayName": "Playground"
            ]) == "Playground")
        check(
            "a macOS variant of CFBundleName still loses to a real display name",
            AppDisplayName.inInfo([
                "CFBundleDisplayName": "Shown", "CFBundleName-macos": "Internal"
            ]) == "Shown")

        // RapidAPI 4.5.5 ships exactly this: blank display name, real `CFBundleName`, Paw's old id.
        let rapidAPI = makeApp(
            "RapidAPI.app",
            info: [
                "CFBundleDisplayName": "", "CFBundleName": "RapidAPI",
                "CFBundleIdentifier": "com.luckymarmot.Paw"
            ])
        check(
            "a bundle with a blank display name is named by CFBundleName",
            rapidAPI?.installedAppName == "RapidAPI")

        let unnamed = makeApp("Mystery.app", info: ["CFBundleIdentifier": "com.example.mystery"])
        check(
            "a bundle naming itself nowhere falls back to its filename",
            unnamed?.installedAppName == "Mystery")

        let blankBoth = makeApp(
            "Ghost.app",
            info: [
                "CFBundleDisplayName": "  ", "CFBundleName": "",
                "CFBundleIdentifier": "com.example.ghost"
            ])
        check(
            "two blank keys still fall back to the filename",
            blankBoth?.installedAppName == "Ghost")

        func makeLocalizedApp(_ fileName: String, table: [String: Any]) -> URL {
            let url = root.appendingPathComponent(fileName)
            let resources = url.appendingPathComponent("Contents/Resources")
            try? fm.createDirectory(at: resources, withIntermediateDirectories: true)
            let data = try? PropertyListSerialization.data(
                fromPropertyList: table, format: .xml, options: 0)
            try? data?.write(to: resources.appendingPathComponent("InfoPlist.loctable"))
            return url
        }

        func names(_ url: URL, region: String? = "en") -> [String] {
            BundleEnglishName.names(
                for: url, base: url.deletingPathExtension().lastPathComponent, developmentRegion: region)
        }

        let calculator = makeLocalizedApp(
            "Calculator.app", table: ["de": ["CFBundleDisplayName": "Rechner"]])
        check("a translation is never indexed", names(calculator) == ["Calculator"])

        let monitor = makeLocalizedApp(
            "Activity Monitor.app",
            table: ["zh_CN": ["CFBundleName": "活动监视器"], "en": ["CFBundleName": "Activity Monitor"]])
        check("a loctable app indexes only its English name", names(monitor) == ["Activity Monitor"])

        // Print Center ships `en_GB` but no `en`; the file name is the English name it already has.
        let printCenter = makeLocalizedApp(
            "Print Center.app", table: ["en_GB": ["CFBundleName": "Print Centre"]])
        check(
            "a regional spelling never relabels the app the file name already names",
            names(printCenter) == ["Print Center"])

        // VoiceMemos.app names itself nowhere on disk, so `en` carries the name the user sees.
        let memos = makeLocalizedApp(
            "VoiceMemos.app",
            table: ["en": ["CFBundleName": "Voice Memos"], "ru": ["CFBundleName": "Диктофон"]])
        check(
            "a translated English name replaces the file name it was written for",
            names(memos) == ["Voice Memos"])

        // Safari's `CFBundleDevelopmentRegion` still reads "English", not "en".
        check(
            "a pre-BCP-47 development region names the same language",
            names(memos, region: "English") == ["Voice Memos"])
        check(
            "a non-English base name stays searchable after its English name",
            names(memos, region: "de") == ["Voice Memos", "VoiceMemos"])
        check(
            "a bundle claiming no region keeps its base name searchable",
            names(memos, region: nil) == ["Voice Memos", "VoiceMemos"])

        let english = root.appendingPathComponent("EnglishStrings.app")
        let lproj = english.appendingPathComponent("Contents/Resources/en.lproj")
        try? fm.createDirectory(at: lproj, withIntermediateDirectories: true)
        try? Data("\"CFBundleDisplayName\" = \"English Strings\";\n".utf8)
            .write(to: lproj.appendingPathComponent("InfoPlist.strings"))
        check("en.lproj strings name the bundle", names(english) == ["English Strings"])

        let trackpad = makeLocalizedApp(
            "TrackpadExtension.appex", table: ["en": ["CFBundleDisplayName": "Trackpad"]])
        check("an identifier its own table renames is never indexed", names(trackpad) == ["Trackpad"])

        try? fm.removeItem(at: root)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
