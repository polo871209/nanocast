import Foundation

@MainActor
@Observable
final class CurrencyRateStore {
    private nonisolated static let fiatEndpoint = URL(
        string: "https://backend.raycast.com/api/v1/currencies")!
    private nonisolated static let cryptoEndpoint = URL(
        string: "https://backend.raycast.com/api/v1/currencies/crypto?symbols="
            + CalcCurrency.cryptoCodes.joined(separator: ","))!
    private static let refreshInterval: TimeInterval = 24 * 3600
    private static let retryInterval: TimeInterval = 30 * 60

    private(set) var rates: CurrencyRates?

    private let fileURL: URL
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var completedAt: Date?

    init() {
        fileURL = AppPaths.caches().appendingPathComponent("currency-rates.json")
        guard let data = try? Data(contentsOf: fileURL),
            let cached = try? JSONDecoder().decode(CurrencyRates.self, from: data)
        else { return }
        rates = cached
        if CurrencyFeed.pricesCoins(cached) { completedAt = cached.fetchedAt }
    }

    func start() {
        pump?.cancel()
        pump = Task { [weak self] in
            while !Task.isCancelled, let self {
                let age = max(0, self.completedAt.map { Date().timeIntervalSince($0) } ?? .infinity)
                guard age >= Self.refreshInterval else {
                    try? await Task.sleep(for: .seconds(Self.refreshInterval - age))
                    continue
                }
                let ok = await self.fetchAndStore()
                try? await Task.sleep(for: .seconds(ok ? Self.refreshInterval : Self.retryInterval))
            }
        }
    }

    private func fetchAndStore() async -> Bool {
        guard let result = await Self.fetch() else { return false }
        rates = result.rates
        guard result.complete, let data = try? JSONEncoder().encode(result.rates) else { return false }
        completedAt = result.rates.fetchedAt
        try? data.write(to: fileURL, options: .atomic)
        return true
    }

    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private nonisolated static func fetch() async -> (rates: CurrencyRates, complete: Bool)? {
        async let fiat = body(of: fiatEndpoint)
        async let crypto = body(of: cryptoEndpoint)
        let (fiatData, cryptoData) = await (fiat, crypto)
        guard let fiatData else { return nil }
        return try? CurrencyFeed.snapshot(fiat: fiatData, crypto: cryptoData, now: Date())
    }

    private nonisolated static func body(of url: URL) async -> Data? {
        let request = URLRequest(url: url, timeoutInterval: 20)
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return data
    }
}
