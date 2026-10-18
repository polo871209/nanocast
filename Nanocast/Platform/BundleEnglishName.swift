import Foundation

enum BundleEnglishName {
    nonisolated static func names(
        for bundleURL: URL, base: String, developmentRegion: String?
    ) -> [String] {
        let resources = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let table = plist(at: resources.appendingPathComponent("InfoPlist.loctable"))
        let strings = plist(at: resources.appendingPathComponent("en.lproj/InfoPlist.strings"))
        var names: [String] = []
        var seen = Set<String>()
        for info in [table?["en"] as? [String: Any], strings].compactMap({ $0 }) {
            if let name = AppDisplayName.inInfo(info), seen.insert(FuzzyMatch.normalized(name)).inserted {
                names.append(name)
            }
        }
        let isEnglishBase = developmentRegion.flatMap(languageCode(of:)) == "en"
        if names.isEmpty || !isEnglishBase, seen.insert(FuzzyMatch.normalized(base)).inserted {
            names.append(base)
        }
        return names
    }

    /// `CFBundleDevelopmentRegion` still ships its pre-BCP-47 spelling: Safari's reads "English".
    private static func languageCode(of region: String) -> String? {
        Locale.Language(identifier: Locale.canonicalLanguageIdentifier(from: region))
            .languageCode?.identifier
    }

    private static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil))
            as? [String: Any]
    }
}
