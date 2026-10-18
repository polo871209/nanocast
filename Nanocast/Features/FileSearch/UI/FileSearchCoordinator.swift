import AppKit

@MainActor
final class FileSearchCoordinator {
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: FileSearchSession
    private let indexer: FileIndexer
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private var sharePicker: NSSharingServicePicker?
    private unowned let core: AppCore

    init(
        settings: AppSettings, appIndex: AppIndex, session: FileSearchSession,
        indexer: FileIndexer, palette: PaletteState, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.session = session
        self.indexer = indexer
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
        indexer.onIndexChanged = { [weak session] in session?.refresh() }
        indexer.onRecentChanged = { [weak session] in session?.refreshRecent() }
    }

    func applyEnabled() {
        appIndex.setCommandsVisible([.searchFiles], settings.fileSearchEnabled)
        indexer.setEnabled(settings.fileSearchEnabled)
        guard !settings.fileSearchEnabled else { return }
        session.cancel()
        if palette.mode == .fileSearch { palette.prepare(mode: .launcher) }
    }

    func applyPolicy() {
        indexer.apply(
            FileSearchPolicy(
                scopes: settings.fileSearchScopes,
                ignorePatterns: settings.fileSearchEffectiveIgnorePatterns,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser))
    }

    var showsFilesInLauncher: Bool {
        settings.fileSearchEnabled && settings.fileSearchShowInLauncher
    }

    var favoriteFiles: [FileSearchResult] {
        guard settings.fileSearchEnabled else { return [] }
        return core.favorites.files(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    func searchFromLauncher(_ query: String) {
        guard showsFilesInLauncher, FileSearchQuery.answersLauncher(query) else {
            session.cancel()
            return
        }
        session.search(query)
    }

    func launcherFiles(for query: String) -> [FileSearchResult] {
        guard settings.fileSearchEnabled, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return []
        }
        let results = showsFilesInLauncher && FileSearchQuery.answersLauncher(query) ? session.results : []
        return FileSearchQuery.launcherResults(query, favorites: favoriteFiles, indexed: results)
    }

    func applyLauncherFiles() {
        guard palette.mode == .launcher else { return }
        searchFromLauncher(palette.query)
    }

    func rebuildIndex() {
        indexer.rebuild()
    }

    func openFullDiskAccessSettings() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Permissions.openFullDiskAccessSettings()
    }

    func show() {
        guard settings.fileSearchEnabled else { return }
        indexer.refreshAccess()
        paletteCoordinator.togglePalette(mode: .fileSearch)
    }

    func activate(_ result: FileSearchResult) {
        if result.opensInPreview {
            openInPreview(result)
        } else {
            paletteCoordinator.hidePalette()
            copyPath(result)
        }
    }

    func openInPreview(_ result: FileSearchResult) {
        open(result, with: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview"))
    }

    func open(_ result: FileSearchResult, with application: URL? = nil) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                if let application {
                    _ = try await NSWorkspace.shared.open(
                        [result.url], withApplicationAt: application, configuration: configuration)
                } else {
                    _ = try await NSWorkspace.shared.open(result.url, configuration: configuration)
                }
            } catch {
                await core.showNotice(
                    title: "Couldn’t Open \(result.name)",
                    message: error.localizedDescription,
                    symbol: result.isDirectory ? "folder" : "doc", tone: .danger)
            }
        }
    }

    func showInFinder(_ result: FileSearchResult) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(result.url)
    }

    func share(_ result: FileSearchResult) {
        guard let provider = NSItemProvider(contentsOf: result.url),
            let anchor = paletteCoordinator.anchorView
        else { return }
        let picker = NSSharingServicePicker(items: [provider])
        sharePicker = picker
        picker.show(
            relativeTo: CGRect(
                x: anchor.bounds.maxX, y: anchor.bounds.midY, width: 0, height: 0),
            of: anchor, preferredEdge: .maxX)
    }

    func copyPath(_ result: FileSearchResult) {
        Paster.copyPlainText(result.id)
        core.showMessage("Copied path")
    }

    func copyName(_ result: FileSearchResult) {
        Paster.copyPlainText(result.name)
        core.showMessage("Copied name")
    }

    func copyFile(_ result: FileSearchResult) {
        PasteboardFiles.write(result.url, to: .general)
        core.showMessage("Copied file")
    }

    func trash(_ result: FileSearchResult) {
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.trashItem(at: result.url, resultingItemURL: nil)
                }.value
                session.remove(result)
                core.showMessage("Moved to Trash")
            } catch {
                await core.showNotice(
                    title: "Couldn’t Move \(result.name) to Trash",
                    message: error.localizedDescription,
                    symbol: "trash", tone: .danger)
            }
        }
    }
}
