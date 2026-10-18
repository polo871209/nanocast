import Foundation

enum SettingsFileIssue: Error, Equatable, Sendable {
    case invalidJSON(String)
    case notAnObject(String?)
    case unknownSetting(String)
    case invalidValue(SettingsFileKey)
    case invalidEntry(SettingsFileKey, String)
    case unreadable
    case unwritable

    var message: String {
        switch self {
        case .invalidJSON(let detail): "not valid JSON — \(detail)"
        case .notAnObject(nil): "the file must hold one JSON object"
        case .notAnObject(let path?): "“\(path)” must be an object"
        case .unknownSetting(let path): "unknown setting “\(path)”"
        case .invalidValue(let key): "“\(key.rawValue)” has a value Nanocast can't use"
        case .invalidEntry(let key, let detail): "“\(key.rawValue)”: \(detail)"
        case .unreadable: "couldn't be read"
        case .unwritable: "couldn't be saved"
        }
    }

    static func summary(_ issues: [SettingsFileIssue]) -> String? {
        guard let first = issues.first else { return nil }
        guard issues.count > 1 else { return "settings.json: \(first.message)" }
        return "settings.json: \(first.message) (+\(issues.count - 1) more)"
    }
}
