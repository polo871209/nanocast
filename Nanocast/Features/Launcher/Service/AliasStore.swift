import Foundation

@MainActor
@Observable
final class AliasStore {
    private let defaults: UserDefaults
    private let defaultsKey = "launcherAliases"

    private(set) var aliases: [String: String]
    private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        aliases = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    func alias(for entryKey: String) -> String? { aliases[entryKey] }

    func setAlias(_ alias: String, for entryKey: String) {
        let value = alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : alias
        guard aliases[entryKey] != value else { return }
        aliases[entryKey] = value
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }

    func removeKeys(_ keys: Set<String>) {
        let remaining = aliases.filter { !keys.contains($0.key) }
        guard remaining.count != aliases.count else { return }
        aliases = remaining
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }

    func replace(_ new: [String: String]) {
        aliases = new.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }
}
