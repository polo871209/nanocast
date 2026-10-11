import AppKit

@MainActor
final class ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.nanocast.internal")

    static let maxTextLength = 32_000

    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive")
    ]

    private let store: ClipboardStore
    private let settings: AppSettings
    private var timer: Timer?
    private var sessionTokens: [NotificationToken] = []
    private var lastChangeCount = 0
    private var isCapturing = false

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    isolated deinit {
        timer?.invalidate()
    }

    func start() {
        guard !isCapturing else { return }
        isCapturing = true
        installSessionObservers()
        startPolling()
    }

    func stop() {
        isCapturing = false
        sessionTokens = []
        stopPolling()
    }

    private func installSessionObservers() {
        guard sessionTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stopPolling() }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.startPolling() }
                }, center: center)
        ]
    }

    private func startPolling() {
        guard isCapturing, timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func prepareForNanocastPasteboardMutation() {
        guard isCapturing else { return }
        poll()
    }

    func synchronizeAfterNanocastPasteboardMutation(changeCount: Int) {
        guard NSPasteboard.general.changeCount == changeCount else { return }
        lastChangeCount = changeCount
    }

    nonisolated static let maxCapturedFiles = 32

    nonisolated static let volatileRoots = [
        "/tmp/", "/var/tmp/", "/var/folders/", NSHomeDirectory() + "/Library/Caches/"
    ]

    nonisolated static func fileURLs(
        on pasteboard: NSPasteboard, volatileRoots roots: [String] = volatileRoots
    ) -> [String]? {
        let durable = PasteboardFiles.urls(on: pasteboard, limit: maxCapturedFiles) {
            isDurable($0, roots: roots)
        }
        guard !durable.isEmpty else { return nil }
        return durable.map(\.standardizedFileURL.path).reversed()
    }

    nonisolated private static func isDurable(_ url: URL, roots: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var path = url.resolvingSymlinksInPath().path
        if path.hasPrefix("/private/") { path.removeFirst("/private".count) }
        return !roots.contains { path.hasPrefix($0) }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if pb.types?.contains(Self.internalType) == true { return }

        if let types = pb.types, !Set(types).isDisjoint(with: Self.sensitiveTypes) { return }

        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleID, settings.clipboardDisabledApps.contains(sourceBundleID) { return }

        if let paths = Self.fileURLs(on: pb) {
            store.addFiles(paths, sourceBundleID: sourceBundleID)
            return
        }

        if let text = pb.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            guard text.count <= Self.maxTextLength else { return }
            store.addText(text, sourceBundleID: sourceBundleID)
            return
        }

        if let type = pb.availableType(from: [.png, .tiff]), let data = pb.data(forType: type) {
            let isPNG = type == .png
            let store = store
            Task.detached(priority: .utility) {
                let png =
                    isPNG
                    ? data
                    : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
                guard let png else { return }
                await store.addImage(png, sourceBundleID: sourceBundleID)
            }
        }
    }
}
