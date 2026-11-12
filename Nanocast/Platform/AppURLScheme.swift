import Foundation

/// This channel's own link scheme: `nanocast`, or `nanocast-dev` for Debug. Set in project.yml.
enum AppURLScheme {
    static let current: String = {
        guard let scheme = Bundle.main.object(forInfoDictionaryKey: "NanocastURLScheme") as? String
        else { preconditionFailure("Info.plist must name NanocastURLScheme") }
        return scheme
    }()
}
