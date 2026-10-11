import Foundation

enum AppDisplayName {
    static func named(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func inInfo(_ info: [String: Any]) -> String? {
        // `CFBundle` reads the `-macos` variant first; Image Playground's loctable ships both.
        named(info["CFBundleDisplayName-macos"]) ?? named(info["CFBundleDisplayName"])
            ?? named(info["CFBundleName-macos"]) ?? named(info["CFBundleName"])
    }
}

extension Bundle {
    var appDisplayName: String {
        infoName("CFBundleDisplayName") ?? infoName("CFBundleName") ?? "Nanocast"
    }

    var installedAppName: String {
        infoName("CFBundleDisplayName") ?? infoName("CFBundleName")
            ?? bundleURL.deletingPathExtension().lastPathComponent
    }

    private func infoName(_ key: String) -> String? {
        AppDisplayName.named(object(forInfoDictionaryKey: key))
    }
}
