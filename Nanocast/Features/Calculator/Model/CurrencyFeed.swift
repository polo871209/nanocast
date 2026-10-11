import Foundation

enum CurrencyFeed {
    private struct FiatPayload: Decodable {
        let success: Bool
        let source: String
        let quotes: [String: Double]
    }

    private struct CryptoPayload: Decodable {
        let success: Bool
        let target: String
        let rates: [String: Double]
    }

    static func snapshot(
        fiat: Data, crypto: Data?, now: Date
    ) throws -> (rates: CurrencyRates, complete: Bool) {
        let payload = try JSONDecoder().decode(FiatPayload.self, from: fiat)
        let base = payload.source
        guard payload.success, base.count == 3 else { throw URLError(.cannotParseResponse) }

        var rates: [String: Double] = [:]
        rates.reserveCapacity(payload.quotes.count + 1)
        for (pair, rate) in payload.quotes where usable(rate) {
            guard pair.count == 6, pair.hasPrefix(base) else { continue }
            rates[String(pair.dropFirst(3))] = rate
        }
        guard !rates.isEmpty else { throw URLError(.cannotParseResponse) }
        rates[base] = 1

        var coins = 0
        if let crypto, let payload = try? JSONDecoder().decode(CryptoPayload.self, from: crypto),
            payload.success, payload.target == base
        {
            for (code, price) in payload.rates where usable(price) && usable(1 / price) {
                rates[code] = 1 / price
                coins += 1
            }
        }

        return (CurrencyRates(base: base, rates: rates, fetchedAt: now), coins > 0)
    }

    static func pricesCoins(_ snapshot: CurrencyRates) -> Bool {
        CalcCurrency.cryptoCodes.contains { snapshot.rates[$0] != nil }
    }

    private static func usable(_ rate: Double) -> Bool {
        rate > 0 && rate.isFinite
    }
}
