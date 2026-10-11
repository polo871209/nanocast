import AppKit
import SwiftUI

@MainActor
@Observable
final class UpdateCoordinator {
    enum Stage: Equatable {
        case checking
        case upToDate
        case localBuild
        case available(AvailableRelease)
        case blocked(UpdateReadiness.Blocker, AvailableRelease)
        case installing(AvailableRelease, UpdateInstaller.Phase)
        case readyToRelaunch
        case failed(UpdateFailure)
    }

    private(set) var stage: Stage = .checking

    private let store: UpdateCheckStore
    private unowned let core: AppCore
    @ObservationIgnored private lazy var window = AppWindowController(
        title: String(localized: "Software Update"), contentSize: UpdateWindowView.initialSize,
        activation: core.activationPolicy)
    @ObservationIgnored private var installTask: Task<Void, Never>?

    init(store: UpdateCheckStore, core: AppCore) {
        self.store = store
        self.core = core
    }

    var runningVersion: String { store.runningVersion?.description ?? String(localized: "unknown") }

    func applyEnabled() {
        core.appIndex.setCommandsVisible([.checkForUpdates], store.channel.updatesItself)
    }

    func applyAutomaticChecking() {
        if core.settings.automaticallyCheckForUpdates {
            store.start()
        } else {
            store.stop()
        }
    }

    func focusExisting() -> Bool {
        window.focus()
    }

    func fit(height: CGFloat) {
        window.fitContent(width: UpdateWindowView.width, height: height)
    }

    func checkForUpdates() {
        guard store.channel.updatesItself else {
            stage = .localBuild
            present()
            return
        }
        if case .installing = stage {
            present()
            return
        }
        stage = .checking
        present()
        Task { [weak self] in
            guard let self else { return }
            let answered = await store.check()
            guard case .checking = stage else { return }
            if let release = store.update {
                stage = .available(release)
            } else if answered {
                stage = .upToDate
            } else {
                stage = .failed(.downloadFailed(String(localized: "Nanocast could not reach GitHub.")))
            }
        }
    }

    func presentIfAvailable(_ release: AvailableRelease) -> Bool {
        guard core.settings.automaticallyCheckForUpdates else { return false }
        switch stage {
        case .installing, .readyToRelaunch:
            return true
        case .checking, .upToDate, .localBuild, .available, .blocked, .failed:
            guard UpdateReadiness.evaluate(core.currentActivity) == nil else { return false }
            stage = .available(release)
            present()
            return true
        }
    }

    func install() {
        guard let release = pendingRelease else { return }
        if let blocker = UpdateReadiness.evaluate(core.currentActivity) {
            stage = .blocked(blocker, release)
            return
        }
        stage = .installing(release, .downloading(received: 0, expected: release.assetSize))
        let installer = self.installer
        let onProgress: @Sendable (UpdateInstaller.Phase) -> Void = { [weak self] phase in
            Task { @MainActor in self?.report(phase, for: release) }
        }
        installTask = Task { [weak self] in
            do {
                try await installer.install(release, onProgress: onProgress)
                self?.stage = .readyToRelaunch
            } catch is CancellationError {
                self?.stage = .available(release)
            } catch let failure as UpdateFailure {
                self?.stage = .failed(failure)
            } catch {
                self?.stage = .failed(.downloadFailed(error.localizedDescription))
            }
        }
    }

    func skip() {
        if let release = pendingRelease { store.skip(release) }
        window.close()
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
    }

    func retry() {
        guard let release = pendingRelease else { return }
        stage = .available(release)
    }

    func dismiss() {
        window.close()
    }

    func relaunch() {
        core.relaunch()
    }

    private func report(_ phase: UpdateInstaller.Phase, for release: AvailableRelease) {
        guard case .installing = stage else { return }
        stage = .installing(release, phase)
    }

    private var pendingRelease: AvailableRelease? {
        switch stage {
        case .available(let release), .blocked(_, let release), .installing(let release, _):
            return release
        case .checking, .upToDate, .localBuild, .readyToRelaunch, .failed:
            return store.update
        }
    }

    private var installer: UpdateInstaller {
        UpdateInstaller(
            bundleURL: Bundle.main.bundleURL,
            stagingDirectory: AppPaths.caches().appendingPathComponent("Updates", isDirectory: true))
    }

    private func present() {
        window.show {
            UpdateWindowView()
                .environment(self)
        }
    }
}
