import AppKit
import Observation

@MainActor
@Observable
final class CustomCommandCoordinator {
    private(set) var editor: CustomCommandEditorSession?
    private let store: CustomCommandStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private unowned let core: AppCore
    @ObservationIgnored private lazy var outputPresenter = CommandOutputPresenter(
        activation: activationPolicy,
        rerun: { [unowned self] in self.runCustomCommand(id: $0) },
        stop: { [unowned self] in self.stopOutputRun(id: $0) },
        openSettings: { [unowned self] in self.settingsCoordinator.showSettings(tab: .commands) })
    private let activationPolicy: ActivationPolicy
    private var liveRun: (id: UUID, stop: @Sendable () -> Void)?

    init(
        store: CustomCommandStore,
        settings: AppSettings,
        appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        hotKeys: HotKeyManager,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        aliases: AliasStore,
        activationPolicy: ActivationPolicy,
        core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.activationPolicy = activationPolicy
        self.core = core
    }

    func applyCustomCommandsPresence() {
        if !settings.customCommandsEnabled {
            if core.palette.mode == .customCommandEditor { cancelCustomCommandEditing() }
            if core.palette.mode == .customCommands {
                core.palette.prepare(mode: .launcher)
            }
        }
        let visible = settings.customCommandsEnabled && settings.customCommandsShowInLauncher
        appIndex.setCustomCommands(visible ? store.commands : [])
        let commands = Set(SettingsTab.commands.ownedCommands)
        appIndex.setCommandsVisible(commands, settings.customCommandsEnabled)
        appIndex.setCommandsListed(commands, settings.customCommandsShowInLauncher)
    }

    func showCustomCommands() {
        guard settings.customCommandsEnabled else { return }
        paletteCoordinator.togglePalette(mode: .customCommands)
    }

    func editCustomCommand(_ command: CustomCommand?) {
        guard settings.customCommandsEnabled else { return }
        editor = CustomCommandEditorSession(command: command)
        paletteCoordinator.showPalette(mode: .customCommandEditor)
    }

    func saveCustomCommand() {
        guard settings.customCommandsEnabled, let editor, editor.canSave else { return }
        do {
            var draft = editor.draft()
            if editor.original == nil {
                try addCustomCommand(draft)
            } else {
                guard let current = store.command(id: editor.id) else {
                    editor.errorMessage = "This command was deleted. Copy your changes before closing."
                    return
                }
                draft.isEnabled = current.isEnabled
                try updateCustomCommand(draft)
            }
            cancelCustomCommandEditing()
        } catch {
            editor.errorMessage = error.localizedDescription
        }
    }

    func cancelCustomCommandEditing() {
        guard core.palette.mode == .customCommandEditor else { return }
        if !core.palette.pop(preservingSelection: true) {
            paletteCoordinator.hidePalette()
            core.palette.prepare(mode: .launcher)
        }
        editor = nil
    }

    func editorDidClose(_ editor: CustomCommandEditorSession) {
        if self.editor === editor { self.editor = nil }
    }

    func chooseWorkingDirectory() {
        guard let editor else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder this command runs in."
        if !editor.workingDirectory.isEmpty {
            panel.directoryURL = URL(
                fileURLWithPath: (editor.workingDirectory as NSString).expandingTildeInPath)
        }
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, self.editor === editor else { return }
        editor.workingDirectory = (url.path as NSString).abbreviatingWithTildeInPath
    }

    @discardableResult
    func addCustomCommand(_ draft: CustomCommand) throws -> CustomCommand {
        try store.add(draft)
    }

    func updateCustomCommand(_ draft: CustomCommand) throws {
        try store.update(draft)
    }

    func setCustomCommandEnabled(_ enabled: Bool, id: UUID) {
        store.setEnabled(enabled, id: id)
    }

    func setCustomCommandShowsInRootSearch(_ shows: Bool, id: UUID) {
        store.setShowsInRootSearch(shows, id: id)
    }

    func deleteCustomCommand(id: UUID) async {
        guard let command = store.command(id: id) else { return }
        guard
            await core.confirm(
                title: "Delete “\(command.name)”?",
                message: "Its shortcut, favorite slot and learned ranking go with it.",
                symbol: command.iconSymbol ?? CustomCommand.sfSymbol,
                confirmTitle: "Delete")
        else { return }
        removeCustomCommandReferences(ids: [id], entryIDs: [command.entryID])
        store.remove(id: id)
    }

    @discardableResult
    func replaceCustomCommands(_ commands: [CustomCommand]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.commands.map { ($0.id, $0) })
        let count = store.replace(with: commands)
        let liveIDs = Set(store.commands.map(\.id))
        let removed = Set(previous.keys).subtracting(liveIDs)
        let removedEntryIDs = Set(removed.compactMap { previous[$0]?.entryID })
        removeCustomCommandReferences(ids: removed, entryIDs: removedEntryIDs)
        return count
    }

    func importScriptDirectory() async {
        guard let directory = chooseScriptDirectory() else { return }
        let drafts = await Task.detached(priority: .userInitiated) {
            RaycastScriptImport.scan(directory: directory)
        }.value
        guard !drafts.isEmpty else {
            await core.showNotice(
                title: "Nothing to Import",
                message: "No Raycast script commands were found in this folder.",
                symbol: CustomCommand.sfSymbol, tone: .neutral)
            return
        }
        guard await confirmScriptImport(count: drafts.count) else { return }
        let added = store.add(contentsOf: drafts)
        guard added > 0 else {
            await core.showNotice(
                title: "Nothing to Import",
                message: "Every script in this folder is already in your library.",
                symbol: CustomCommand.sfSymbol, tone: .neutral)
            return
        }
        await core.showNotice(
            title: "Scripts Imported",
            message: importSummary(added: added, offered: drafts.count),
            symbol: CustomCommand.sfSymbol, tone: .success)
    }

    /// An accessory app must activate first, or the panel opens behind the frontmost app.
    private func chooseScriptDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose a folder of Raycast script commands."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func confirmScriptImport(count: Int) async -> Bool {
        await core.confirm(
            title: count == 1 ? "Import 1 script?" : "Import \(count) scripts?",
            message: """
                Imported commands run these files with your user account. Only import scripts you \
                trust.
                """,
            symbol: CustomCommand.sfSymbol, confirmTitle: "Import",
            confirmRole: .standard)
    }

    private func importSummary(added: Int, offered: Int) -> String {
        let commands = added == 1 ? "1 command" : "\(added) commands"
        guard offered > added else { return "Imported \(commands)." }
        return "Imported \(commands). Skipped \(offered - added) already in your library."
    }

    func runCustomCommand(id: UUID, values: [String: String] = [:]) {
        guard settings.customCommandsEnabled else { return }
        guard let command = store.command(id: id), command.isEnabled else { return }
        guard let arguments = command.positionalValues(from: values) else {
            paletteCoordinator.showArguments(of: AppEntry(command), values: values)
            return
        }
        perform(command, arguments: arguments)
    }

    func focusOutputWindow() -> Bool {
        outputPresenter.focusExisting()
    }

    private func perform(_ command: CustomCommand, arguments: [String]) {
        guard settings.customCommandsEnabled else { return }
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        Task {
            if command.requiresConfirmation {
                guard
                    await core.confirm(
                        title: command.name,
                        message: "Are you sure you want to run this command?\n\n\(command.command)",
                        symbol: command.symbol, confirmTitle: "Run",
                        tone: .neutral, confirmRole: .standard)
                else { return }
            }
            guard !command.showsOutput else {
                await streamOutput(of: command, arguments: arguments)
                return
            }
            let result = await ShellCommandRunner.run(
                command.command, arguments: arguments,
                loadingShellEnvironment: command.loadsShellEnvironment,
                workingDirectory: command.workingDirectory)
            await report(command, result: result)
        }
    }

    private func streamOutput(of command: CustomCommand, arguments: [String]) async {
        let session = ShellCommandRunner.stream(
            command.command, arguments: arguments,
            loadingShellEnvironment: command.loadsShellEnvironment,
            workingDirectory: command.workingDirectory)
        let runID = outputPresenter.begin(
            commandID: command.id, name: command.name, commandText: command.command,
            symbol: command.symbol)
        liveRun = (runID, session.stop)
        defer { if liveRun?.id == runID { liveRun = nil } }

        for await event in session.events {
            switch event {
            case .output(let text):
                outputPresenter.append(text, to: runID)
            case .finished(let result):
                outputPresenter.finish(
                    CommandOutcome(
                        summary: summary(of: result),
                        hint: shellEnvironmentHint(command: command, result: result),
                        succeeded: result.succeeded, finishedAt: Date()),
                    for: runID)
            }
        }
    }

    private func stopOutputRun(id: UUID) {
        guard let liveRun, liveRun.id == id else { return }
        liveRun.stop()
    }

    private func removeCustomCommandReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.customCommand(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }

    private func report(_ command: CustomCommand, result: ShellCommandResult) async {
        guard !result.succeeded else {
            if command.showsConfirmation {
                core.showMessage(result.lastOutputLine ?? "Ran \(command.name)")
            }
            return
        }
        let hint = shellEnvironmentHint(command: command, result: result)
        guard
            await core.reportFailure(
                title: "“\(command.name)” Failed",
                message: failureMessage(command: command, result: result),
                symbol: command.symbol, recovery: hint == nil ? nil : "Open Settings…")
        else { return }
        settingsCoordinator.showSettings(tab: .commands)
    }

    private func summary(of result: ShellCommandResult) -> String {
        switch result.termination {
        case .launchFailed: return "The shell could not be started."
        case .stopped: return "Stopped"
        case .exited(let status):
            return status == 0
                ? "Finished successfully."
                : "The command exited with status \(status)."
        }
    }

    private func failureMessage(command: CustomCommand, result: ShellCommandResult) -> String {
        var parts = [summary(of: result)]
        if case .launchFailed(let detail) = result.termination { parts.append(detail) }
        if let standardError = result.standardError { parts.append(standardError) }
        if let hint = shellEnvironmentHint(command: command, result: result) { parts.append(hint) }
        return parts.joined(separator: "\n\n")
    }

    private func shellEnvironmentHint(
        command: CustomCommand, result: ShellCommandResult
    ) -> String? {
        guard case .exited(status: 127) = result.termination, !command.loadsShellEnvironment else {
            return nil
        }
        return """
            If this is a shell alias or function, turn on Load Shell Environment for this command.
            """
    }
}
