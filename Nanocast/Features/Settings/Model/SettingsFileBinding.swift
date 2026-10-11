import Foundation

@MainActor
struct SettingsFileBinding {
    let key: SettingsFileKey
    let read: () -> SettingsFileJSON
    let write: (SettingsFileJSON) -> [SettingsFileIssue]

    init(
        _ key: SettingsFileKey, read: @escaping () -> SettingsFileJSON,
        write: @escaping (SettingsFileJSON) -> [SettingsFileIssue]
    ) {
        self.key = key
        self.read = read
        self.write = write
    }

    init<Root: AnyObject, Value: SettingsFileValue>(
        _ key: SettingsFileKey, _ root: Root, _ path: ReferenceWritableKeyPath<Root, Value>,
        accept: @escaping (Value) -> Value? = { $0 }
    ) {
        self.init(
            key,
            read: { root[keyPath: path].settingsJSON },
            write: { json in
                guard let value = Value(settingsJSON: json).flatMap(accept) else {
                    return [.invalidValue(key)]
                }
                if root[keyPath: path] != value { root[keyPath: path] = value }
                return []
            })
    }
}
