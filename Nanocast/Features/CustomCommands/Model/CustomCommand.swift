import Foundation

struct CustomCommandArgument: Codable, Hashable, Sendable {
    var name: String
    var isOptional: Bool

    init(name: String, isOptional: Bool = false) {
        self.name = name
        self.isOptional = isOptional
    }

    static let limit = 3

    static func fieldID(at index: Int) -> String { "$\(index + 1)" }

    static func sanitized(_ arguments: [CustomCommandArgument]) -> [CustomCommandArgument] {
        let cleaned = arguments.compactMap { argument -> CustomCommandArgument? in
            var cleaned = argument
            cleaned.name = argument.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.name.isEmpty, !cleaned.name.contains("\0") else { return nil }
            return cleaned
        }
        return Array(cleaned.prefix(limit))
    }
}

struct CustomCommand: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "custom-command:"
    static let sfSymbol = "terminal"

    let id: UUID
    var name: String
    var command: String
    var isEnabled: Bool
    var showsInRootSearch: Bool
    var loadsShellEnvironment: Bool
    var requiresConfirmation: Bool
    var showsConfirmation: Bool
    var arguments: [CustomCommandArgument]
    var showsOutput: Bool
    var workingDirectory: String?
    var iconSymbol: String?

    init(
        id: UUID = UUID(), name: String, command: String, isEnabled: Bool = true,
        showsInRootSearch: Bool = true, loadsShellEnvironment: Bool = false,
        requiresConfirmation: Bool = false, showsConfirmation: Bool = false,
        arguments: [CustomCommandArgument] = [],
        showsOutput: Bool = false, workingDirectory: String? = nil, iconSymbol: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.isEnabled = isEnabled
        self.showsInRootSearch = showsInRootSearch
        self.loadsShellEnvironment = loadsShellEnvironment
        self.requiresConfirmation = requiresConfirmation
        self.showsConfirmation = showsConfirmation
        self.arguments = arguments
        self.showsOutput = showsOutput
        self.workingDirectory = workingDirectory
        self.iconSymbol = iconSymbol
    }

    var symbol: String { iconSymbol ?? Self.sfSymbol }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    func positionalValues(from values: [String: String]) -> [String]? {
        let positional = arguments.indices.map {
            values[CustomCommandArgument.fieldID(at: $0)] ?? ""
        }
        let complete = zip(arguments, positional).allSatisfy { $0.isOptional || !$1.isEmpty }
        return complete ? positional : nil
    }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, command, isEnabled, showsInRootSearch, loadsShellEnvironment
        case requiresConfirmation, showsConfirmation, arguments, showsOutput, workingDirectory
        case iconSymbol
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        showsInRootSearch =
            try container.decodeIfPresent(Bool.self, forKey: .showsInRootSearch) ?? true
        loadsShellEnvironment =
            try container.decodeIfPresent(Bool.self, forKey: .loadsShellEnvironment) ?? false
        requiresConfirmation =
            try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
        showsConfirmation =
            try container.decodeIfPresent(Bool.self, forKey: .showsConfirmation) ?? false
        arguments =
            try container.decodeIfPresent([CustomCommandArgument].self, forKey: .arguments) ?? []
        showsOutput = try container.decodeIfPresent(Bool.self, forKey: .showsOutput) ?? false
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
    }
}

extension String {
    fileprivate var cleanedPathComponent: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("\0") ? nil : trimmed
    }
}

enum CustomCommandValidationError: LocalizedError {
    case emptyName
    case emptyCommand
    case duplicateName
    case invalidCharacter

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the command."
        case .emptyCommand: return "Enter a command to run."
        case .duplicateName: return "A custom command with this name already exists."
        case .invalidCharacter: return "Names and commands cannot contain null characters."
        }
    }
}

@MainActor
@Observable
final class CustomCommandStore {
    private static let defaultsKey = "customCommands"

    private let defaults: UserDefaults
    private(set) var commands: [CustomCommand]
    @ObservationIgnored var onChange: (([CustomCommand]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([CustomCommand].self, from: $0) } ?? []
        commands = Self.sanitized(decoded)
        if commands != decoded { persist() }
    }

    func command(id: UUID) -> CustomCommand? {
        commands.first { $0.id == id }
    }

    func command(entryID: String) -> CustomCommand? {
        CustomCommand.id(fromEntryID: entryID).flatMap(command)
    }

    func matching(_ query: String) -> [CustomCommand] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return commands.filter {
            $0.isEnabled && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
        }
    }

    @discardableResult
    func add(_ draft: CustomCommand) throws -> CustomCommand {
        let value = try validated(draft, against: commands)
        commit(commands + [value])
        return value
    }

    @discardableResult
    func add(contentsOf drafts: [CustomCommand]) -> Int {
        var updated = commands
        let existing = commands.count
        for draft in drafts {
            guard let value = try? validated(draft, against: updated) else { continue }
            updated.append(value)
        }
        commit(updated)
        return updated.count - existing
    }

    func update(_ draft: CustomCommand) throws {
        guard let index = commands.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft, against: commands)
        var updated = commands
        updated[index] = value
        commit(updated)
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = commands.firstIndex(where: { $0.id == id }),
            commands[index].isEnabled != enabled
        else { return }
        var updated = commands
        updated[index].isEnabled = enabled
        commit(updated)
    }

    func setShowsInRootSearch(_ shows: Bool, id: UUID) {
        guard let index = commands.firstIndex(where: { $0.id == id }),
            commands[index].showsInRootSearch != shows
        else { return }
        var updated = commands
        updated[index].showsInRootSearch = shows
        commit(updated)
    }

    @discardableResult
    func remove(id: UUID) -> CustomCommand? {
        guard let index = commands.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = commands
        let removed = updated.remove(at: index)
        commit(updated)
        return removed
    }

    @discardableResult
    func replace(with newCommands: [CustomCommand]) -> Int {
        let updated = Self.sanitized(newCommands)
        commit(updated)
        return updated.count
    }

    private func validated(
        _ draft: CustomCommand, against existing: [CustomCommand]
    ) throws -> CustomCommand {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.command = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        value.arguments = CustomCommandArgument.sanitized(draft.arguments)
        value.workingDirectory = draft.workingDirectory?.cleanedPathComponent
        value.iconSymbol = draft.iconSymbol?.cleanedPathComponent
        guard !value.name.isEmpty else { throw CustomCommandValidationError.emptyName }
        guard !value.command.isEmpty else { throw CustomCommandValidationError.emptyCommand }
        guard !value.name.contains("\0"), !value.command.contains("\0") else {
            throw CustomCommandValidationError.invalidCharacter
        }
        guard
            !existing.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw CustomCommandValidationError.duplicateName }
        return value
    }

    private func commit(_ updated: [CustomCommand]) {
        guard updated != commands else { return }
        commands = updated
        persist()
        onChange?(updated)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func sanitized(_ values: [CustomCommand]) -> [CustomCommand] {
        var ids = Set<UUID>()
        var names = Set<String>()
        var result: [CustomCommand] = []
        for value in values {
            var cleaned = value
            cleaned.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.command = value.command.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.arguments = CustomCommandArgument.sanitized(value.arguments)
            cleaned.workingDirectory = value.workingDirectory?.cleanedPathComponent
            cleaned.iconSymbol = value.iconSymbol?.cleanedPathComponent
            let foldedName = cleaned.name.folding(options: [.caseInsensitive], locale: .current)
            guard !cleaned.name.isEmpty, !cleaned.command.isEmpty, !cleaned.name.contains("\0"),
                !cleaned.command.contains("\0"), ids.insert(cleaned.id).inserted,
                names.insert(foldedName).inserted
            else { continue }
            result.append(cleaned)
        }
        return result
    }
}
