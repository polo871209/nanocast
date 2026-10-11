import AppKit
import AVFoundation

@MainActor
@Observable
final class DictationCoordinator {
    private enum Phase { case idle, starting, listening, transcribing, stopping }

    private let settings: AppSettings
    private let hotKeys: HotKeyManager
    let models: DictationModelStore
    private let capture = DictationCapture()
    private let audioDucker: DictationAudioDucker
    private let panel = DictationPanelController()
    private let injector: TextInjector
    private let showMessage: (String, DialogTone) -> Void
    private let confirmEnable: () async -> Bool
    @ObservationIgnored private var phase: Phase = .idle
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var enableTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var liveOffset = 0
    @ObservationIgnored private var liveText = ""
    @ObservationIgnored private var liveDeliveryFailed = false
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var finishWhenStarted = false
    @ObservationIgnored private var target: InjectionTarget?

    init(
        settings: AppSettings, hotKeys: HotKeyManager, models: DictationModelStore,
        injector: TextInjector, audioDucker: DictationAudioDucker,
        confirmEnable: @escaping () async -> Bool,
        showMessage: @escaping (String, DialogTone) -> Void
    ) {
        self.settings = settings
        self.hotKeys = hotKeys
        self.models = models
        self.injector = injector
        self.audioDucker = audioDucker
        self.confirmEnable = confirmEnable
        self.showMessage = showMessage
        panel.onAccept = { [weak self] in self?.accept() }
        panel.onCancel = { [weak self] in self?.cancel() }
        capture.onLevels = { [weak self] in self?.panel.state.levels = $0 }
        capture.onLimit = { [weak self] in self?.accept() }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.dictationEnabled else { return }
        guard enabled else {
            settings.dictationEnabled = false
            enableTask?.cancel()
            cancel()
            return
        }
        guard enableTask == nil else { return }
        NSApp.activate()
        enableTask = Task { [weak self] in
            guard let self else { return }
            defer { enableTask = nil }
            guard await confirmEnable(), !Task.isCancelled else { return }
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled else { return }
            guard granted else {
                showMessage(
                    String(localized: "Allow Nanocast to use the microphone in System Settings"), .danger)
                return
            }
            settings.dictationEnabled = true
            if settings.dictationDestination.pastes { Permissions.ensureAccessibility() }
        }
    }

    func downloadModel(_ model: DictationModel) async {
        do { try await models.download(model) } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch { showMessage(error.localizedDescription, .danger) }
    }

    func removeModel(_ model: DictationModel) async {
        do { try await models.delete(model) } catch { showMessage(error.localizedDescription, .danger) }
    }

    var holdShortcutIssue: String? {
        guard let binding = hotKeys.binding(for: .dictation) else { return nil }
        guard binding.shortcut != nil || binding.holdKey != nil else {
            return String(localized: "Record a single modifier or a key combination for hold to talk.")
        }
        if let owner = hotKeys.conflictOwner(of: binding, excluding: .dictation) {
            return String(localized: "This shortcut is also used by \(owner). Record another shortcut.")
        }
        return nil
    }

    func pressed() {
        guard settings.dictationEnabled else { return }
        if phase == .stopping { return }
        if settings.dictationMode == .pushToTalk,
            hotKeys.binding(for: .dictation)?.shortcut == nil,
            hotKeys.binding(for: .dictation)?.holdKey == nil
        {
            showMessage(
                String(localized: "Hold to talk needs a key combination or a single modifier"), .danger)
            return
        }
        if phase != .idle {
            if settings.dictationMode == .toggle { finish() }
            return
        }
        begin(target: InjectionTarget.current())
    }

    private func finish() {
        if phase == .starting {
            finishWhenStarted = true
        } else {
            accept()
        }
    }

    private func begin(target: InjectionTarget?) {
        guard models.isInstalled(settings.dictationModel) else {
            showMessage(String(localized: "Download the dictation model in Settings first"), .danger)
            return
        }
        token = UUID()
        let current = token
        phase = .starting
        finishWhenStarted = false
        liveOffset = 0
        liveText = ""
        self.target = target
        audioDucker.begin()
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await capture.start(microphoneID: settings.dictationMicrophone)
                guard token == current, settings.dictationEnabled else {
                    _ = await capture.stop()
                    return
                }
                phase = .listening
                panel.show()
                startLiveInsertion(token: current)
                if finishWhenStarted { accept() }
            } catch {
                guard token == current else { return }
                reset()
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    func released() {
        guard settings.dictationMode == .pushToTalk else { return }
        if phase == .starting { finishWhenStarted = true }
        if phase == .listening { accept() }
    }

    func accept() {
        guard phase == .listening else { return }
        phase = .transcribing
        panel.state.phase = .transcribing
        audioDucker.end()
        // A cancelled chunk keeps its audio: the final pass starts at liveOffset, losing nothing.
        let pendingLive = liveTask
        liveTask = nil
        pendingLive?.cancel()
        let current = token
        let model = settings.dictationModel
        let language = settings.dictationLanguage
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            await pendingLive?.value
            let samples = await capture.stop()
            // Queued chunks land first: reset would drop them, and the remainder spaces after them.
            if !liveText.isEmpty { await injector.drain() }
            guard token == current else { return }
            let tail = liveOffset < samples.count ? Array(samples[liveOffset...]) : []
            let destination = settings.dictationDestination
            if tail.count < 1_600 {
                if liveText.isEmpty {
                    reset(cancelTranscription: false)
                    showMessage(String(localized: "No speech was recorded"), .danger)
                } else {
                    finishWithoutRemainder(destination)
                }
                return
            }
            do {
                let transcript = try await models.transcribe(
                    tail, model: model,
                    language: language)
                guard token == current else { return }
                let context = destination.pastes ? insertionContext() : nil
                let text = DictationTextFormatter.format(
                    transcript, context: context,
                    adaptCapitalization: settings.dictationAdaptsCapitalization)
                let target = self.target
                let assembled = liveText + text
                guard !text.isEmpty else { finishWithoutRemainder(destination); return }
                panel.close()
                if destination.pastes {
                    injector.deliver(
                        text, target: target,
                        isValid: { [weak self] in self?.token == current },
                        onDelivered: { [weak self] in
                            guard let self, token == current else { return }
                            let lost = liveDeliveryFailed
                            if destination.copies { Paster.copyPlainText(assembled) }
                            reset(cancelTranscription: false)
                            if lost, destination.pastes {
                                showMessage(
                                    String(localized: "Couldn't paste some dictation into this app"),
                                    .danger)
                            }
                        },
                        onFailed: { [weak self] in
                            guard let self, token == current else { return }
                            reset(cancelTranscription: false)
                            if destination.copies { Paster.copyPlainText(assembled) }
                            showMessage(String(localized: "Couldn't paste dictation into this app"), .danger)
                        })
                } else {
                    Paster.copyPlainText(text)
                    reset(cancelTranscription: false)
                }
            } catch {
                guard token == current else { return }
                reset(cancelTranscription: false)
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    private func finishWithoutRemainder(_ destination: DictationDestination) {
        let text = liveText
        let lost = liveDeliveryFailed
        reset(cancelTranscription: false)
        if !text.isEmpty, destination.copies { Paster.copyPlainText(text) }
        if lost, destination.pastes {
            showMessage(String(localized: "Couldn't paste some dictation into this app"), .danger)
        }
    }

    /// Chunk spacing from the caret, else from pasted text, so chunks never glue without a space.
    private func insertionContext() -> DictationTextFormatter.Context? {
        if let context = DictationInsertionContext.read(in: target) { return context }
        guard !liveText.isEmpty else { return nil }
        return DictationTextFormatter.Context(before: liveText.suffix(512), after: Substring())
    }

    private func startLiveInsertion(token current: UUID) {
        guard settings.dictationDestination.pastes, settings.dictationLiveInsertion else { return }
        liveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, token == current, phase == .listening else { return }
                guard settings.dictationLiveInsertion else { return }
                await flushLiveChunk(token: current)
            }
        }
    }

    private func flushLiveChunk(token current: UUID) async {
        let snapshot = capture.snapshot()
        guard token == current else { return }
        let fresh = snapshot.count - liveOffset
        guard fresh >= DictationAudioChunks.minimumLiveSamples else { return }
        guard
            fresh >= DictationAudioChunks.maximumLiveSamples
                || DictationAudioChunks.endsInPause(in: snapshot, from: liveOffset, to: snapshot.count)
        else { return }
        let end = DictationAudioChunks.liveCut(in: snapshot, from: liveOffset, to: snapshot.count)
        guard end > liveOffset else { return }
        let overlap = DictationAudioChunks.liveOverlapStart(in: snapshot, before: liveOffset)
        let segment = Array(snapshot[overlap..<end])
        do {
            let transcript = try await models.transcribe(
                segment, model: settings.dictationModel,
                language: settings.dictationLanguage)
            guard token == current else { return }
            liveOffset = end
            let context = insertionContext()
            let text = DictationTextFormatter.format(
                transcript, context: context,
                adaptCapitalization: settings.dictationAdaptsCapitalization)
            let stripped = DictationTextFormatter.stripEcho(text, after: liveText)
            guard !stripped.isEmpty else { return }
            liveText += stripped
            let target = self.target
            injector.deliver(
                stripped, target: target,
                isValid: { [weak self] in self?.token == current },
                onDelivered: {},
                onFailed: { [weak self] in
                    guard let self, token == current else { return }
                    liveDeliveryFailed = true
                })
        } catch {
            // The final pass starts at liveOffset, so it covers what this chunk left behind.
        }
    }

    func cancel() {
        guard phase != .stopping, phase != .idle || !settings.dictationEnabled else { return }
        let pendingStart = startTask
        let pendingTranscription = transcriptionTask
        let pendingLive = liveTask
        reset()
        phase = .stopping
        let current = token
        stopTask = Task { [weak self] in
            guard let self else { return }
            await pendingStart?.value
            _ = await capture.stop()
            await pendingTranscription?.value
            await pendingLive?.value
            if !settings.dictationEnabled { await models.stop() }
            if token == current { phase = .idle; stopTask = nil }
        }
    }

    func prepareForTermination() {
        enableTask?.cancel()
        cancel()
        audioDucker.restoreImmediately()
        models.prepareForTermination()
    }

    private func reset(cancelTranscription: Bool = true) {
        token = UUID()
        if cancelTranscription { transcriptionTask?.cancel() }
        liveTask?.cancel()
        liveTask = nil
        liveOffset = 0
        liveText = ""
        liveDeliveryFailed = false
        startTask = nil
        transcriptionTask = nil
        phase = .idle
        target = nil
        panel.close()
        audioDucker.end()
    }
}
