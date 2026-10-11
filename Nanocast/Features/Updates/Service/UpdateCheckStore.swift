import Foundation

@MainActor
@Observable
final class UpdateCheckStore {
    private nonisolated static let endpoint = URL(
        string: "https://api.github.com/repos/\(ReleaseFeed.repository)/releases?per_page=20")!
    private static let refreshInterval: TimeInterval = 24 * 3600
    private static let retryInterval: TimeInterval = 2 * 3600
    private static let withheldInterval: TimeInterval = 120
    private static let withheldRetryLimit = 15
    private static let startupDelay = Duration.seconds(30)

    let channel: ReleaseChannel
    let runningVersion: AppVersion?

    private(set) var latest: AvailableRelease?
    private(set) var lastCheckedAt: Date?
    private(set) var isChecking = false

    @ObservationIgnored var onUpdateAvailable: (@MainActor (AvailableRelease) -> Bool)?

    private let fileURL: URL
    @ObservationIgnored private let fetch: @Sendable () async -> Data?
    private var skippedVersion: AppVersion?
    @ObservationIgnored private var announcedVersion: AppVersion?
    @ObservationIgnored private var withheldRetries = 0
    @ObservationIgnored private var pump: Task<Void, Never>?

    init(
        channel: ReleaseChannel = ReleaseChannel(bundleID: Bundle.main.bundleIdentifier),
        runningVersion: AppVersion? = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap(AppVersion.init),
        fileURL: URL = AppPaths.caches().appendingPathComponent("update-check.json"),
        fetch: @escaping @Sendable () async -> Data? = UpdateCheckStore.body
    ) {
        self.channel = channel
        self.runningVersion = runningVersion
        self.fileURL = fileURL
        self.fetch = fetch
        guard let data = try? Data(contentsOf: fileURL),
            let cache = try? JSONDecoder().decode(Cache.self, from: data)
        else { return }
        latest = cache.latest
        lastCheckedAt = cache.lastCheckedAt
        skippedVersion = cache.skippedVersion
    }

    deinit { pump?.cancel() }

    var update: AvailableRelease? {
        guard let runningVersion else { return nil }
        return ReleaseFeed.offer(latest, running: runningVersion, skipped: nil)
    }

    var unskippedUpdate: AvailableRelease? {
        guard let runningVersion else { return nil }
        return ReleaseFeed.offer(latest, running: runningVersion, skipped: skippedVersion)
    }

    func start(after delay: Duration = UpdateCheckStore.startupDelay) {
        guard channel.updatesItself, runningVersion != nil else { return }
        stop()
        pump = Task { [weak self] in
            try? await Task.sleep(for: delay)
            while !Task.isCancelled {
                guard let wait = await self?.advance() else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        withheldRetries = 0
    }

    @discardableResult
    func check() async -> Bool {
        guard channel.updatesItself, !isChecking else { return false }
        isChecking = true
        defer { isChecking = false }
        guard let data = await fetch(), !Task.isCancelled else { return false }
        latest = ReleaseFeed.newest(from: data, channel: channel)
        lastCheckedAt = Date()
        persist()
        return true
    }

    func skip(_ release: AvailableRelease) {
        skippedVersion = release.version
        persist()
    }

    private func advance() async -> TimeInterval {
        let age = max(0, lastCheckedAt.map { Date().timeIntervalSince($0) } ?? .infinity)
        var wait = Self.refreshInterval - age
        if wait <= 0 {
            wait = await check() ? Self.refreshInterval : Self.retryInterval
        }
        if announce() {
            withheldRetries = 0
        } else if withheldRetries < Self.withheldRetryLimit {
            withheldRetries += 1
            wait = min(wait, Self.withheldInterval)
        }
        return wait
    }

    private func announce() -> Bool {
        guard !Task.isCancelled else { return true }
        guard let release = unskippedUpdate, announcedVersion != release.version else { return true }
        guard onUpdateAvailable?(release) ?? true else { return false }
        announcedVersion = release.version
        return true
    }

    private func persist() {
        let cache = Cache(
            lastCheckedAt: lastCheckedAt, latest: latest, skippedVersion: skippedVersion)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private struct Cache: Codable {
        var lastCheckedAt: Date?
        var latest: AvailableRelease?
        var skippedVersion: AppVersion?
    }

    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private nonisolated static func body() async -> Data? {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        // GitHub rejects an API request carrying no User-Agent outright.
        request.setValue("Nanocast", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return data
    }
}
