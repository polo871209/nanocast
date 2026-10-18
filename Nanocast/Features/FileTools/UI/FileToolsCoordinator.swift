import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class FileToolsCoordinator: HealthCheckable {
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: FileToolsSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private weak var healthTicker: HealthTicker?
    private unowned let core: AppCore
    private var jobTask: Task<Void, Never>?
    private var pendingTransfer: FileToolTransfer.Mode?
    private lazy var finderTab = FinderTabTap { [weak self] in self?.openFinderSelection() }

    private static let decodableTypes = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])

    init(
        settings: AppSettings, appIndex: AppIndex, session: FileToolsSession, palette: PaletteState,
        paletteCoordinator: PaletteCoordinator, healthTicker: HealthTicker, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.healthTicker = healthTicker
        self.core = core
    }

    var isEnabled: Bool { settings.fileToolsEnabled }

    var isFinderTabInstalled: Bool { finderTab.isInstalled }

    private var context: FileToolCatalog.Context {
        FileToolCatalog.Context(decodableImages: Self.decodableTypes, canPickFolders: settings.fileSearchEnabled)
    }

    func applyEnabled() {
        appIndex.setCommandsVisible([.fileTools], settings.fileToolsEnabled)
        applyFinderTab()
        guard !settings.fileToolsEnabled else {
            session.restore(settings.fileToolsOptions.compactMap(FileToolOption.init(token:)))
            return
        }
        jobTask?.cancel()
        jobTask = nil
        session.reset()
        if palette.mode == .fileTools || palette.mode == .fileToolsDestination { palette.prepare(mode: .launcher) }
    }

    private func applyFinderTab() {
        guard settings.fileToolsEnabled, settings.fileToolsFinderTab else {
            finderTab.uninstall()
            healthTicker?.unsubscribe(self)
            return
        }
        healthTicker?.subscribe(self)
        if !finderTab.install() { Permissions.ensureAccessibility() }
    }

    func healthCheck() {
        guard settings.fileToolsEnabled, settings.fileToolsFinderTab else { return }
        if Permissions.isAccessibilityTrusted() {
            finderTab.install()
        } else {
            finderTab.uninstall()
        }
    }

    // MARK: Entry points

    func show() {
        guard settings.fileToolsEnabled else { return }
        if paletteCoordinator.targetApp?.bundleIdentifier == FinderSelectionReader.bundleIdentifier {
            openFinderSelection()
        } else {
            showFileSearchInstead()
        }
    }

    func open(_ file: FileSearchResult) {
        guard settings.fileToolsEnabled else { return }
        present(FileToolsSubject(url: file.url, isDirectory: file.isDirectory, origin: .search))
        paletteCoordinator.navigate(to: .fileTools)
    }

    private func openFinderSelection() {
        guard settings.fileToolsEnabled else { return }
        Task {
            do {
                let items = try await FinderSelectionReader.read()
                guard settings.fileToolsEnabled else { return }
                guard !items.isEmpty else {
                    return core.showMessage("Select files in Finder first", tone: .neutral)
                }
                present(FileToolsSubject(items: items, origin: .finder))
                paletteCoordinator.showPalette(mode: .fileTools, seeding: "")
            } catch FinderSelectionReader.Failure.denied {
                await explainAutomationDenial()
            } catch {
                core.showMessage("Couldn’t read the Finder selection", tone: .danger)
            }
        }
    }

    private func showFileSearchInstead() {
        if settings.fileSearchEnabled {
            core.fileSearchCoordinator.show()
        } else {
            core.showMessage("Select files in Finder first", tone: .neutral)
        }
    }

    private func explainAutomationDenial() async {
        guard
            await core.reportFailure(
                title: "Nanocast Can’t Read the Finder Selection",
                message: "Turn on Finder for Nanocast in Privacy & Security ▸ Automation, then try again.",
                symbol: "wand.and.sparkles", recovery: "Open System Settings…"),
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Options

    func choose(_ option: FileToolOption, for tool: FileTool) {
        session.choose(option, for: tool)
        settings.fileToolsOptions = session.options.values.map(\.token).sorted()
    }

    func cycleOption(of tool: FileTool, backwards: Bool) {
        guard let next = tool.option(after: session.option(for: tool), backwards: backwards) else { return }
        choose(next, for: tool)
    }

    // MARK: Jobs

    func run(_ tool: FileTool, fields: [FileToolField: String]) {
        guard let subject = session.subject else { return }
        guard session.job == nil else {
            core.showMessage("Wait for the current job to finish", tone: .neutral)
            return
        }
        let parameters: FileToolParameters
        switch FileToolFieldParser.parameters(for: tool.fields, values: fields) {
        case .success(let parsed): parameters = parsed
        case .failure(let error): return core.showMessage(error.message, tone: .danger)
        }
        switch tool.kind {
        case .pinImage: pin(subject)
        case .copyPath: copyPaths()
        case .airDrop: airDrop(subject)
        case .moveTo: pickDestination(.move)
        case .copyTo: pickDestination(.copy)
        case .copyText, .readQRCode: copyText(tool, from: subject)
        default: process(tool, subject: subject, parameters: parameters)
        }
    }

    func cancelJob() {
        guard let job = session.job else { return }
        jobTask?.cancel()
        jobTask = nil
        _ = session.endJob(job.id)
    }

    private func process(_ tool: FileTool, subject: FileToolsSubject, parameters: FileToolParameters) {
        let option = session.option(for: tool)
        let context = context
        let batches: [(tool: FileTool, sources: [URL])] =
            tool.combinesSources
            ? [(tool, subject.urls)]
            : subject.items.map { (FileToolCatalog.tool(id: tool.id, for: $0, context: context) ?? tool, [$0.url]) }
        let inputBytes = subject.urls.compactMap(Self.byteCount(of:)).reduce(0, +)
        let id = session.startJob(tool)
        let session = session
        jobTask = Task { [weak self] in
            var outputs: [URL] = []
            do {
                for (index, (tool, sources)) in batches.enumerated() {
                    guard
                        let destination = FileToolOutputName.destination(
                            for: tool, option: option, parameters: parameters, sources: sources,
                            isTaken: { FileManager.default.fileExists(atPath: $0.path) })
                    else { continue }
                    let request = tool.request(
                        option: option, parameters: parameters, sources: sources, destination: destination)
                    let count = Double(batches.count)
                    try await FileToolWorker.run(request, timeout: tool.timeout) { fraction in
                        Task { @MainActor in session.report((Double(index) + fraction) / count, for: id) }
                    }
                    outputs.append(destination)
                }
                self?.finish(id, outputs: outputs, inputBytes: inputBytes, origin: subject.origin)
            } catch is CancellationError {
                _ = self?.session.endJob(id)
            } catch {
                await self?.fail(id, subject: subject, finished: outputs, error: error)
            }
        }
    }

    private func copyText(_ tool: FileTool, from subject: FileToolsSubject) {
        let changeCount = NSPasteboard.general.changeCount
        let id = session.startJob(tool)
        jobTask = Task { [weak self] in
            do {
                var texts: [String] = []
                for item in subject.items {
                    texts.append(try await Self.text(of: item, tool: tool))
                }
                guard let self, session.endJob(id) else { return }
                let text = texts.filter { !$0.isEmpty }.joined(separator: "\n\n")
                guard !text.isEmpty else {
                    let empty =
                        tool.kind == .readQRCode
                        ? "No QR code found" : "No text found"
                    return core.showMessage(empty, tone: .neutral)
                }
                guard NSPasteboard.general.changeCount == changeCount else {
                    return core.showMessage("Clipboard changed, text not copied", tone: .neutral)
                }
                Paster.copyPlainText(text)
                leaveForFinder(subject.origin)
                core.showMessage("Copied text")
            } catch is CancellationError {
                _ = self?.session.endJob(id)
            } catch {
                await self?.fail(id, subject: subject, finished: [], error: error)
            }
        }
    }

    private static func text(of item: FileToolsSubject.Item, tool: FileTool) async throws -> String {
        if tool.kind == .readQRCode {
            let request = tool.request(
                option: nil, parameters: FileToolParameters(), sources: [item.url], destination: item.url)
            return try await FileToolWorker.read(request, timeout: tool.timeout)
        }
        let isPDF = item.type?.conforms(to: .pdf) == true
        return try await ClipboardTextWorker.extract(at: item.url, as: isPDF ? .pdf : .screenshot)
    }

    private func finish(_ id: Int, outputs: [URL], inputBytes: Int, origin: FileToolsSubject.Origin) {
        guard session.endJob(id) else { return }
        let outputBytes = outputs.compactMap(Self.byteCount(of:)).reduce(0, +)
        let outcome = FileToolsSession.Outcome(
            kind: .saved, outputs: outputs, inputBytes: inputBytes > 0 ? inputBytes : nil,
            outputBytes: outputBytes > 0 ? outputBytes : nil)
        let items = outputs.map { FileToolsSubject.Item(url: $0, isDirectory: Self.isDirectory($0)) }
        present(FileToolsSubject(items: items, origin: origin), outcome: outcome)
        Paster.copyPlainText(Self.pathList(outputs))
        if returnsToFinder(origin) {
            reveal(outputs)
        } else if isOnScreen {
            palette.query = ""
            palette.selection = 0
            return
        }
        if outputs.count == 1, let output = outputs.first {
            core.showMessage("Saved \(output.lastPathComponent) and copied its path")
        } else {
            core.showMessage("Saved \(outputs.count) files and copied their paths")
        }
    }

    private func fail(_ id: Int, subject: FileToolsSubject, finished: [URL], error: any Error) async {
        guard session.endJob(id) else { return }
        if !finished.isEmpty {
            let items = finished.map { FileToolsSubject.Item(url: $0, isDirectory: Self.isDirectory($0)) }
            present(FileToolsSubject(items: items, origin: subject.origin))
        }
        let message =
            error is FileToolWorker.Failure || error is ClipboardTextWorker.Failure
            ? "The file couldn’t be read, or the new file couldn’t be written."
            : error.localizedDescription
        let name = subject.isBatch ? "\(subject.items.count) files" : subject.first?.name ?? ""
        await core.showNotice(
            title: "Couldn’t Process \(name)", message: message,
            symbol: "exclamationmark.triangle", tone: .danger)
    }

    private var isOnScreen: Bool {
        paletteCoordinator.isVisible && palette.mode == .fileTools
    }

    // MARK: Actions

    private func pin(_ subject: FileToolsSubject) {
        let frame = paletteCoordinator.panelFrame
        let screen = NSScreen.screens.first { frame.map($0.frame.intersects) ?? false } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let bounds = CGSize(width: visible.width / 2, height: visible.height / 2)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            for item in subject.items {
                guard
                    let pin = await FileToolPinLoader.load(
                        item.url, fitting: bounds, backingScale: screen.backingScaleFactor)
                else {
                    core.showMessage("Couldn’t open \(item.name)", tone: .danger)
                    continue
                }
                core.screenshotCoordinator.pin(pin.image, scale: pin.scale, centeredIn: visible)
            }
        }
    }

    func copyPaths() {
        guard let subject = session.subject else { return }
        Paster.copyPlainText(Self.pathList(subject.urls))
        leaveForFinder(subject.origin)
        core.showMessage(subject.isBatch ? "Copied paths" : "Copied path")
    }

    private func returnsToFinder(_ origin: FileToolsSubject.Origin) -> Bool {
        guard origin == .finder else { return false }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return isOnScreen || front == FinderSelectionReader.bundleIdentifier
    }

    private func reveal(_ urls: [URL]) {
        if isOnScreen { paletteCoordinator.hidePalette(restoreFocus: false) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func leaveForFinder(_ origin: FileToolsSubject.Origin) {
        guard origin == .finder, isOnScreen else { return }
        paletteCoordinator.hidePalette(restoreFocus: true)
    }

    private static func pathList(_ urls: [URL]) -> String {
        urls.map(\.path).joined(separator: "\n")
    }

    private func airDrop(_ subject: FileToolsSubject) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: subject.urls)
        else {
            return core.showMessage("AirDrop isn’t available", tone: .danger)
        }
        service.perform(withItems: subject.urls)
    }

    private func pickDestination(_ mode: FileToolTransfer.Mode) {
        pendingTransfer = mode
        paletteCoordinator.navigate(to: .fileToolsDestination)
    }

    var destinationTitle: String {
        pendingTransfer == .copy ? "Copy Here" : "Move Here"
    }

    func transfer(into folder: FileSearchResult) {
        guard let mode = pendingTransfer, let subject = session.subject, folder.isDirectory else { return }
        guard session.job == nil else {
            return core.showMessage("Wait for the current job to finish", tone: .neutral)
        }
        _ = palette.pop(preservingSelection: true)
        Task { [weak self] in
            guard let conflict = await self?.resolveConflict(moving: subject.urls, into: folder) else { return }
            self?.startTransfer(mode, subject: subject, into: folder, conflict: conflict)
        }
    }

    private func resolveConflict(moving sources: [URL], into folder: FileSearchResult) async -> FileToolTransfer.Conflict? {
        let conflicts = FileToolTransfer.conflicts(sources, in: folder.url)
        guard let first = conflicts.first else { return .keepBoth }
        let choice = await core.choose(
            title: conflicts.count == 1
                ? "“\(first.lastPathComponent)” Already Exists in \(folder.name)"
                : "\(conflicts.count) Items Already Exist in \(folder.name)",
            message: "Replace moves the existing items to the Trash.",
            symbol: "doc.on.doc",
            options: [
                DialogAction(title: "Keep Both"),
                DialogAction(title: "Replace", role: .destructive),
                DialogAction(title: "Cancel", role: .cancel)
            ], defaultIndex: 0)
        switch choice {
        case 0: return .keepBoth
        case 1: return .replace
        default: return nil
        }
    }

    private func startTransfer(
        _ mode: FileToolTransfer.Mode, subject: FileToolsSubject, into folder: FileSearchResult,
        conflict: FileToolTransfer.Conflict
    ) {
        guard settings.fileToolsEnabled else { return }
        guard session.job == nil else {
            return core.showMessage("Wait for the current job to finish", tone: .neutral)
        }
        let id = session.startJob(FileTool(mode == .move ? .moveTo : .copyTo))
        jobTask = Task { [weak self] in
            do {
                let landed = try await FileToolTransfer.run(mode, subject.urls, into: folder.url, conflict: conflict)
                self?.finishTransfer(id, mode: mode, landed: landed, folder: folder, origin: subject.origin)
            } catch is CancellationError {
                _ = self?.session.endJob(id)
            } catch {
                await self?.fail(id, subject: subject, finished: [], error: error)
            }
        }
    }

    private func finishTransfer(
        _ id: Int, mode: FileToolTransfer.Mode, landed: [URL], folder: FileSearchResult,
        origin: FileToolsSubject.Origin
    ) {
        guard session.endJob(id) else { return }
        let items = landed.map { FileToolsSubject.Item(url: $0, isDirectory: Self.isDirectory($0)) }
        let kind: FileToolsSession.Outcome.Kind = mode == .move ? .moved(folder: folder.name) : .copied(folder: folder.name)
        present(
            FileToolsSubject(items: items, origin: origin),
            outcome: FileToolsSession.Outcome(kind: kind, outputs: landed, inputBytes: nil, outputBytes: nil))
        if returnsToFinder(origin) {
            reveal(landed)
        } else if isOnScreen {
            return
        }
        core.showMessage(
            mode == .move ? "Moved to \(folder.name)" : "Copied to \(folder.name)")
    }

    // MARK: Subject

    func showSubjectInFinder() {
        guard let subject = session.subject else { return }
        NSWorkspace.shared.activateFileViewerSelecting(subject.urls)
        paletteCoordinator.hidePalette(restoreFocus: false)
    }

    func searchResult(for item: FileToolsSubject.Item) -> FileSearchResult {
        FileSearchResult(
            url: item.url, isDirectory: item.isDirectory, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    private func present(_ subject: FileToolsSubject, outcome: FileToolsSession.Outcome? = nil) {
        session.begin(subject, tools: FileToolCatalog.tools(for: subject, context: context), outcome: outcome)
    }

    private static func byteCount(of url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}
