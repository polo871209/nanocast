import Foundation

@MainActor
@Observable
final class HotKeyManager {
    var onTogglePalette: (() -> Void)?
    var onDictationPressed: (() -> Void)?
    var onDictationReleased: (() -> Void)?
    var onDictationCancelled: (() -> Void)?
    var dictationEnabled = false {
        didSet {
            guard dictationEnabled != oldValue else { return }
            if !dictationEnabled { onDictationCancelled?() }
            syncModifierTaps()
        }
    }
    var dictationHoldToTalk = false {
        didSet {
            guard dictationHoldToTalk != oldValue else { return }
            onDictationCancelled?()
            syncModifierTaps()
        }
    }
    var onRunCommand: ((CommandID) -> Void)?
    var onRunCustomCommand: ((UUID) -> Void)?
    var onRunSystemAction: ((SystemAction.ID) -> Void)?
    var onRunWindowCommand: ((WindowCommand.ID) -> Void)?
    var onRunWindowLayout: ((UUID) -> Void)?
    var onEnterRoom: ((UUID) -> Void)?
    var onRunCustomWindowSize: ((UUID) -> Void)?
    var displayName: ((HotKeyAction) -> String?)?
    var allowsAction: ((HotKeyAction) -> Bool)?

    var recordingAction: HotKeyAction? {
        didSet {
            guard recordingAction != oldValue else { return }
            let recording = recordingAction != nil
            if recording, dictationEnabled, dictationHoldToTalk { onDictationCancelled?() }
            if recording { secureInputPressedActions.removeAll(keepingCapacity: true) }
            center.isPaused = recording
            modifierTapMonitor.isPaused = recording
            if secureInputEquivalentsIncludeShift != nil { syncSecureInputEquivalents() }
            if let recordingAction {
                capture.start(action: recordingAction, hotKeys: self)
            } else {
                capture.stop()
            }
        }
    }

    let modifierTapMonitor = ModifierTapMonitor()
    let capture = ShortcutCaptureSession()

    private let defaults: UserDefaults
    private let center = HotKeyCenter()
    private var modifierTaps: [HotKeyBinding: HotKeyAction] = [:]
    private var secureInputEquivalentsIncludeShift: Bool?
    private var secureInputEquivalentIDs: [String] = []
    private var secureInputReplacedActions: [HotKeyAction] = []
    private var secureInputPressedActions: [String: HotKeyAction] = [:]
    private var secureInputHint: KeyShortcut?
    private static let secureInputHintID = "secureInputHint"
    private var bindings: [HotKeyAction: HotKeyBinding] = [:]
    private(set) var revision = 0
    var bindsDictationKey: Bool { bindings.values.contains { $0.shortcut?.isDictationKey == true } }
    @ObservationIgnored private var candidateActionsCache: [HotKeyAction]?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let boundKey = "boundAppBundleIDs"
    private let boundPaneKey = "boundPaneBundleIDs"
    private let boundCustomCommandKey = "boundCustomCommandIDs"
    private let boundWindowLayoutKey = "boundWindowLayoutIDs"
    private let boundWindowRoomKey = "boundWindowRoomIDs"
    private let boundCustomWindowSizeKey = "boundCustomWindowSizeIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start(
        customCommandIDs: Set<UUID>, windowLayoutIDs: Set<UUID>,
        windowRoomIDs: Set<UUID>, customWindowSizeIDs: Set<UUID>
    ) {
        prune(key: boundCustomCommandKey, live: customCommandIDs) { .customCommand(id: $0) }
        prune(key: boundWindowLayoutKey, live: windowLayoutIDs) { .windowLayout(id: $0) }
        prune(key: boundWindowRoomKey, live: windowRoomIDs) { .windowRoom(id: $0) }
        prune(key: boundCustomWindowSizeKey, live: customWindowSizeIDs) {
            .customWindowSize(id: $0)
        }
        for action in candidateActions { bindings[action] = storedBinding(for: action) }
        revision &+= 1

        for action in candidateActions { register(action) }
        if secureInputEquivalentsIncludeShift != nil { syncSecureInputEquivalents() }

        modifierTapMonitor.onTrigger = { [weak self] binding in
            guard let self, let action = modifierTaps[binding] else { return }
            perform(action)
        }
        modifierTapMonitor.onHoldPressed = { [weak self] in self?.perform(.dictation) }
        modifierTapMonitor.onHoldReleased = { [weak self] in self?.onDictationReleased?() }
        modifierTapMonitor.onHoldCancelled = { [weak self] in self?.onDictationCancelled?() }
        modifierTapMonitor.start()
        syncModifierTaps()
    }

    var boundBundleIDs: [String] {
        defaults.stringArray(forKey: boundKey) ?? []
    }

    var boundPaneBundleIDs: [String] {
        defaults.stringArray(forKey: boundPaneKey) ?? []
    }

    var boundCustomCommandIDs: [UUID] { boundIDs(key: boundCustomCommandKey) }

    var boundWindowLayoutIDs: [UUID] { boundIDs(key: boundWindowLayoutKey) }

    var boundWindowRoomIDs: [UUID] { boundIDs(key: boundWindowRoomKey) }

    var boundCustomWindowSizeIDs: [UUID] { boundIDs(key: boundCustomWindowSizeKey) }

    func removeAppBindings(where isUninstalled: (String) -> Bool) {
        for bundleID in boundBundleIDs where isUninstalled(bundleID) {
            let action = HotKeyAction.app(bundleID: bundleID)
            if recordingAction == action { recordingAction = nil }
            setBinding(nil, for: action)
        }
    }

    func binding(for action: HotKeyAction) -> HotKeyBinding? { bindings[action] }

    private func storedBinding(for action: HotKeyAction) -> HotKeyBinding? {
        guard
            let json = defaults.string(forKey: action.defaultsKey),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? decoder.decode(HotKeyBinding.self, from: data)
    }

    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        if action == .dictation, binding != self.binding(for: action) { onDictationCancelled?() }
        let previous = bindings[action]
        clearSecureInputEquivalents()
        if let binding,
            let data = try? encoder.encode(binding),
            let json = String(data: data, encoding: .utf8)
        {
            bindings[action] = binding
            defaults.set(json, forKey: action.defaultsKey)
        } else {
            bindings[action] = nil
            defaults.removeObject(forKey: action.defaultsKey)
        }
        revision &+= 1
        center.unregister(id: action.defaultsKey)
        register(action)

        switch action {
        case .app(let bundleID):
            index(bundleID, bound: binding != nil, key: boundKey)
        case .settingsPane(let bundleID):
            index(bundleID, bound: binding != nil, key: boundPaneKey)
        case .customCommand(let id):
            index(id, bound: binding != nil, key: boundCustomCommandKey)
        case .windowLayout(let id):
            index(id, bound: binding != nil, key: boundWindowLayoutKey)
        case .windowRoom(let id):
            index(id, bound: binding != nil, key: boundWindowRoomKey)
        case .customWindowSize(let id):
            index(id, bound: binding != nil, key: boundCustomWindowSizeKey)
        case .togglePalette, .dictation, .command, .systemAction, .windowCommand:
            break
        }
        candidateActionsCache = nil
        if previous?.usesModifierTapMonitor == true || binding?.usesModifierTapMonitor == true {
            syncModifierTaps()
        }
        if secureInputEquivalentsIncludeShift != nil { syncSecureInputEquivalents() }
    }

    /// Secure Input hides the Hyper chord from every tap, so its combos also register with ⌃.
    func setSecureInputEquivalents(includesShift: Bool?) {
        guard includesShift != secureInputEquivalentsIncludeShift else { return }
        secureInputEquivalentsIncludeShift = includesShift
        syncSecureInputEquivalents()
    }

    func setSecureInputHint(_ shortcut: KeyShortcut?, onPress: @escaping () -> Void) {
        guard shortcut != secureInputHint else { return }
        secureInputHint = shortcut
        center.unregister(id: Self.secureInputHintID)
        guard let shortcut else { return }
        center.register(id: Self.secureInputHintID, shortcut: shortcut, onKeyDown: { _ in onPress() })
    }

    private func syncSecureInputEquivalents() {
        clearSecureInputEquivalents()
        guard let includesShift = secureInputEquivalentsIncludeShift else { return }
        let chord = KeyShortcut.hyperChord(includesShift: includesShift)
        let actions = candidateActions
        let originalActions = actions.reduce(into: [KeyShortcut: HotKeyAction]()) { result, action in
            if let shortcut = binding(for: action)?.shortcut { result[shortcut] = action }
        }
        for action in actions {
            guard let equivalent = binding(for: action)?.shortcut?.secureInputEquivalent(of: chord)
            else { continue }
            let original = originalActions[equivalent]
            if let original {
                center.unregister(id: original.defaultsKey)
                secureInputReplacedActions.append(original)
            }
            let id = "secureInputEquivalent." + action.defaultsKey
            var isPressed = false
            center.register(
                id: id, shortcut: equivalent,
                onKeyDown: { [weak self] flags in
                    guard let self else { return }
                    if !isPressed {
                        isPressed = true
                        secureInputPressedActions[id] =
                            ModifierKey.rightControl.isHeld(in: flags) ? action : original
                    }
                    if let selected = secureInputPressedActions[id] { perform(selected) }
                },
                onKeyUp: { [weak self] in
                    isPressed = false
                    if self?.secureInputPressedActions.removeValue(forKey: id) == .dictation {
                        self?.onDictationReleased?()
                    }
                })
            secureInputEquivalentIDs.append(id)
        }
    }

    private func clearSecureInputEquivalents() {
        if secureInputPressedActions.values.contains(.dictation) { onDictationCancelled?() }
        secureInputPressedActions.removeAll(keepingCapacity: true)
        secureInputEquivalentIDs.forEach { center.unregister(id: $0) }
        secureInputEquivalentIDs.removeAll(keepingCapacity: true)
        secureInputReplacedActions.forEach(register)
        secureInputReplacedActions.removeAll(keepingCapacity: true)
    }

    func retargetHyperBindings(includesShift: Bool) {
        for action in candidateActions {
            guard let shortcut = bindings[action]?.shortcut else { continue }
            let retargeted = shortcut.retargetingHyper(includesShift: includesShift)
            guard retargeted != shortcut else { continue }
            let binding = HotKeyBinding.combo(retargeted)
            guard conflictOwner(of: binding, excluding: action) == nil else { continue }
            setBinding(binding, for: action)
        }
    }

    func conflictOwner(of binding: HotKeyBinding, excluding action: HotKeyAction) -> String? {
        for candidate in candidateActions where candidate != action {
            guard let other = self.binding(for: candidate) else { continue }
            let holdsModifier =
                dictationHoldToTalk
                && (action == .dictation && binding.holdKey != nil
                    || candidate == .dictation && other.holdKey != nil)
            if binding.conflicts(with: other, holdsModifier: holdsModifier) {
                return displayName(of: candidate)
            }
        }
        return nil
    }

    private var candidateActions: [HotKeyAction] {
        if let candidateActionsCache { return candidateActionsCache }
        var actions = HotKeyAction.builtInActions
        actions += boundBundleIDs.map { .app(bundleID: $0) }
        actions += boundPaneBundleIDs.map { .settingsPane(bundleID: $0) }
        actions += boundCustomCommandIDs.map { .customCommand(id: $0) }
        actions += boundWindowLayoutIDs.map { .windowLayout(id: $0) }
        actions += boundWindowRoomIDs.map { .windowRoom(id: $0) }
        actions += boundCustomWindowSizeIDs.map { .customWindowSize(id: $0) }
        actions += SystemAction.ID.allCases.map { .systemAction(id: $0) }
        actions += WindowCommand.ID.allCases.map { .windowCommand(id: $0) }
        candidateActionsCache = actions
        return actions
    }

    private func displayName(of action: HotKeyAction) -> String {
        switch action {
        case .togglePalette:
            return "App Launcher"
        case .dictation:
            return "Dictation"
        case .command(let id):
            return id.name
        case .app(let bundleID), .settingsPane(let bundleID):
            return displayName?(action) ?? bundleID
        case .customCommand:
            return displayName?(action) ?? "Custom Command"
        case .systemAction(let id):
            return SystemActionCatalog.action(id: id).name
        case .windowCommand(let id):
            return WindowCommandCatalog.command(id: id)?.name ?? "Window Command"
        case .windowLayout:
            return displayName?(action) ?? "Window Layout"
        case .windowRoom:
            return displayName?(action) ?? "Room"
        case .customWindowSize:
            return displayName?(action) ?? "Custom Size"
        }
    }

    private func register(_ action: HotKeyAction) {
        guard let shortcut = binding(for: action)?.shortcut else { return }
        center.register(
            id: action.defaultsKey, shortcut: shortcut,
            onKeyDown: { [weak self] _ in self?.perform(action) },
            onKeyUp: action == .dictation ? { [weak self] in self?.onDictationReleased?() } : nil)
    }

    private func syncModifierTaps() {
        modifierTaps = [:]
        let dictationBinding = binding(for: .dictation)
        let holdKey = dictationHoldToTalk ? dictationBinding?.holdKey : nil
        for action in candidateActions {
            guard let binding = binding(for: action), binding.usesModifierTapMonitor else { continue }
            if action == .dictation, !dictationEnabled { continue }
            if action == .dictation, dictationHoldToTalk {
                guard holdKey != nil, conflictOwner(of: binding, excluding: action) == nil else {
                    continue
                }
            }
            modifierTaps[binding] = action
        }
        modifierTapMonitor.update(
            bound: Set(modifierTaps.keys),
            holdKey: dictationBinding.flatMap { modifierTaps[$0] == .dictation ? holdKey : nil })
    }

    private func perform(_ action: HotKeyAction) {
        guard allowsAction?(action) ?? true else { return }
        switch action {
        case .togglePalette: onTogglePalette?()
        case .dictation: onDictationPressed?()
        case .command(let id): onRunCommand?(id)
        case .app(let bundleID): AppLauncher.toggle(bundleID: bundleID)
        case .settingsPane(let bundleID): AppLauncher.openSettingsPane(bundleID: bundleID)
        case .customCommand(let id): onRunCustomCommand?(id)
        case .systemAction(let id): onRunSystemAction?(id)
        case .windowCommand(let id): onRunWindowCommand?(id)
        case .windowLayout(let id): onRunWindowLayout?(id)
        case .windowRoom(let id): onEnterRoom?(id)
        case .customWindowSize(let id): onRunCustomWindowSize?(id)
        }
    }

    private func boundIDs(key: String) -> [UUID] {
        (defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))
    }

    private func index(_ id: UUID, bound: Bool, key: String) {
        var set = Set(boundIDs(key: key))
        if bound { set.insert(id) } else { set.remove(id) }
        persist(set, key: key)
    }

    private func index(_ id: String, bound: Bool, key: String) {
        var set = Set(defaults.stringArray(forKey: key) ?? [])
        if bound { set.insert(id) } else { set.remove(id) }
        defaults.set(Array(set), forKey: key)
    }

    private func prune(key: String, live: Set<UUID>, action: (UUID) -> HotKeyAction) {
        let stored = Set(boundIDs(key: key))
        for id in stored.subtracting(live) {
            defaults.removeObject(forKey: action(id).defaultsKey)
        }
        persist(stored.intersection(live), key: key)
    }

    private func persist(_ ids: Set<UUID>, key: String) {
        defaults.set(ids.map { $0.uuidString.lowercased() }.sorted(), forKey: key)
    }
}
