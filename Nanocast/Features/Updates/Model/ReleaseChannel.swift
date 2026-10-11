import Foundation

enum ReleaseChannel: Sendable {
    case stable
    case development

    init(bundleID: String?) {
        self = bundleID == "com.nanocast.app" ? .stable : .development
    }

    var updatesItself: Bool { self == .stable }

    func accepts(prerelease: Bool) -> Bool {
        updatesItself && !prerelease
    }
}
