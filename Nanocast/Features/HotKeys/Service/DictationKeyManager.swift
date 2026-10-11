import AppKit

/// Lends 🎤 to Nanocast as F20. See docs/features/hotkeys.md#the-dictation-key.
@MainActor
final class DictationKeyManager: HealthCheckable {
    var onProblem: ((String) -> Void)?
    weak var healthTicker: HealthTicker?

    private let hotKeys: HotKeyManager
    private let instanceLock: RemapInstanceLock
    private let remapper: KeyboardRemapper
    private var sessionTokens: [NotificationToken] = []
    private var hotKeysObservation: ObservationTracking.Token?
    private var isRunning = false
    private var isSessionActive = true

    init(
        hotKeys: HotKeyManager, defaults: UserDefaults = .standard,
        lockURL: URL = .temporaryDirectory.appending(path: "com.nanocast.dictation-key.lock")
    ) {
        self.hotKeys = hotKeys
        let instanceLock = RemapInstanceLock(url: lockURL)
        self.instanceLock = instanceLock
        remapper = KeyboardRemapper(
            defaults: defaults, recoveryKey: "dictationKeyKeyboardMappings", instanceLock: instanceLock)
    }

    func start() {
        isRunning = true
        remapper.clearLeftovers()
        observeHotKeys()
        observeSession()
        apply()
    }

    func prepareForTermination() {
        isRunning = false
        healthTicker?.unsubscribe(self)
        sessionTokens.removeAll()
        hotKeysObservation = nil
        remapper.apply(nil)
        instanceLock.release()
    }

    func healthCheck() {
        apply()
    }

    private var isWanted: Bool {
        hotKeys.recordingAction != nil || hotKeys.bindsDictationKey
    }

    private func apply() {
        guard isRunning else { return }
        let wanted = isWanted && isSessionActive ? HIDKeyMapping.dictationKeyToF20 : nil
        guard wanted == nil || instanceLock.acquire() else {
            healthTicker?.subscribe(self)
            return
        }
        healthTicker?.unsubscribe(self)
        let isChange = wanted != remapper.mapping
        if !remapper.apply(wanted), wanted != nil, isChange, hotKeys.bindsDictationKey {
            onProblem?("macOS refused to remap the Dictation key")
        }
        if wanted == nil { instanceLock.release() }
    }

    private func observeHotKeys() {
        hotKeysObservation = observeChanges(of: { [weak self] in self?.isWanted }) { [weak self] in
            self?.apply()
        }
    }

    /// HID mappings are system-wide.
    private func observeSession() {
        let center = NSWorkspace.shared.notificationCenter
        let transitions = [
            (NSWorkspace.sessionDidResignActiveNotification, false),
            (NSWorkspace.sessionDidBecomeActiveNotification, true)
        ]
        sessionTokens = transitions.map { name, isActive in
            NotificationToken(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.isSessionActive = isActive
                        self.apply()
                    }
                }, center: center)
        }
    }
}
