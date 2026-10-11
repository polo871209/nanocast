import AppKit

@MainActor
final class WindowSwitchCoordinator: HealthCheckable {
    private static let revealDelay = Duration.milliseconds(100)
    private static let previewInterval = Duration.milliseconds(100)

    private let settings: AppSettings
    private let hotKeys: HotKeyManager
    private let session = WindowSwitchSession()
    private let recency = AppRecencyMonitor()
    private let controller: WindowSwitchController
    private weak var healthTicker: HealthTicker?
    private lazy var tap = WindowSwitchTap { [weak self] in self?.handle($0) }
    private var reveal: Task<Void, Never>?
    private var previews: Task<Void, Never>?

    init(settings: AppSettings, hotKeys: HotKeyManager, healthTicker: HealthTicker) {
        self.settings = settings
        self.hotKeys = hotKeys
        self.healthTicker = healthTicker
        controller = WindowSwitchController { settings.interfaceSize.metrics }
    }

    func applyEnabled() {
        guard settings.navigationEnabled else {
            dismiss()
            tap.uninstall()
            recency.stop()
            healthTicker?.unsubscribe(self)
            return
        }
        applyTrigger()
        recency.start()
        healthTicker?.subscribe(self)
        if !tap.install() { Permissions.ensureAccessibility() }
        WindowPreviewCapture.requestPermission()
    }

    func applyTrigger() {
        let shortcut =
            hotKeys.recordingAction == nil ? hotKeys.binding(for: .windowSwitcher)?.shortcut : nil
        let trigger = shortcut.map {
            WindowSwitchChord.Trigger(
                keyCode: $0.carbonKeyCode, modifiers: UInt64($0.modifierFlags.rawValue))
        }
        guard trigger != tap.trigger else { return }
        dismiss()
        tap.trigger = trigger
    }

    func healthCheck() {
        guard settings.navigationEnabled else { return }
        if !Permissions.isAccessibilityTrusted() {
            dismiss()
            tap.uninstall()
        } else if !tap.isInstalled {
            tap.install()
        }
    }

    private func handle(_ action: WindowSwitchChord.Action) {
        switch action {
        case .open(let backward): open(backward: backward)
        case .step(let delta): session.step(by: delta)
        case .commit: commit()
        case .cancel: dismiss()
        }
    }

    private func open(backward: Bool) {
        close()
        let snapshot = WindowSwitchSweep.snapshot(
            excluding: Set(settings.windowSwitcherExcludedApps))
        let entries = WindowSwitchOrder.sorted(snapshot.entries, recency: recency.order)
        guard !entries.isEmpty else { return tap.endSwitching() }
        let selection = WindowSwitchOrder.initialSelection(
            in: entries,
            frontmost: NSWorkspace.shared.frontmostApplication
                .map { WindowInventory.owningProcess(of: $0).processIdentifier },
            backward: backward)
        session.present(entries, elements: snapshot.elements, selection: selection)
        reveal = Task { [weak self] in
            try? await Task.sleep(for: Self.revealDelay)
            guard !Task.isCancelled else { return }
            self?.show()
        }
    }

    private func show() {
        controller.show(session) { [weak self] index in
            self?.session.selection = index
            self?.commit()
        }
        guard WindowPreviewCapture.isPermitted else { return }
        let windowIDs = session.entries.compactMap(\.windowID)
        let pixelHeight = Int(Theme.Size.switcherThumbnail.height * 2)
        previews = Task { [session] in
            await WindowPreviewCapture.stream(
                windowIDs, pixelHeight: pixelHeight, interval: Self.previewInterval
            ) { session.setPreview($1, for: $0) }
        }
    }

    private func commit() {
        let element = session.selectedElement
        dismiss()
        guard let element, !element.app.isTerminated else { return }
        AXWindowAccess.focus(element.window, in: element.application, of: element.app)
    }

    private func dismiss() {
        close()
        tap.endSwitching()
    }

    private func close() {
        reveal?.cancel()
        reveal = nil
        previews?.cancel()
        previews = nil
        controller.hide()
        session.reset()
    }
}
