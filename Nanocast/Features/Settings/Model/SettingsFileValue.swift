import Foundation

protocol SettingsFileValue: Equatable {
    init?(settingsJSON: SettingsFileJSON)
    var settingsJSON: SettingsFileJSON { get }
}

protocol SettingsFileRawValue: SettingsFileValue, RawRepresentable
where RawValue: SettingsFileValue {}

extension SettingsFileRawValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let rawValue = RawValue(settingsJSON: settingsJSON) else { return nil }
        self.init(rawValue: rawValue)
    }

    var settingsJSON: SettingsFileJSON { rawValue.settingsJSON }
}

protocol SettingsFileToken: SettingsFileValue, CaseIterable {
    var settingsToken: SettingsFileJSON { get }
}

extension SettingsFileToken {
    init?(settingsJSON: SettingsFileJSON) {
        guard let match = Self.allCases.first(where: { $0.settingsToken == settingsJSON }) else {
            return nil
        }
        self = match
    }

    var settingsJSON: SettingsFileJSON { settingsToken }
}

extension Bool: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let value = settingsJSON.bool else { return nil }
        self = value
    }

    var settingsJSON: SettingsFileJSON { .bool(self) }
}

extension Int: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let value = settingsJSON.int else { return nil }
        self = value
    }

    var settingsJSON: SettingsFileJSON { .number(Double(self)) }
}

extension String: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let value = settingsJSON.string else { return nil }
        self = value
    }

    var settingsJSON: SettingsFileJSON { .string(self) }
}

extension Array: SettingsFileValue where Element: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let items = settingsJSON.items else { return nil }
        var values: [Element] = []
        values.reserveCapacity(items.count)
        for item in items {
            guard let value = Element(settingsJSON: item) else { return nil }
            values.append(value)
        }
        self = values
    }

    var settingsJSON: SettingsFileJSON { .array(map(\.settingsJSON)) }
}

extension Optional: SettingsFileValue where Wrapped: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        if settingsJSON == .null {
            self = .none
            return
        }
        guard let value = Wrapped(settingsJSON: settingsJSON) else { return nil }
        self = .some(value)
    }

    var settingsJSON: SettingsFileJSON { map(\.settingsJSON) ?? .null }
}
