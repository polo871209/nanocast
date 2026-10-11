import Foundation

struct CurrencyDef: Equatable, Sendable {
    let code: String
    let name: String
}

struct CurrencyRates: Codable, Equatable, Sendable {
    let base: String
    let rates: [String: Double]
    let fetchedAt: Date

    func rate(for code: String) -> Double? {
        if let rate = rates[code], rate > 0, rate.isFinite { return rate }
        return code == base ? 1 : nil
    }

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let source = rate(for: from), let target = rate(for: to) else { return nil }
        let output = amount / source * target
        return output.isFinite ? output : nil
    }
}

enum CalcCurrency {
    enum ConversionParse: Equatable {
        case value(input: Double, from: CurrencyDef, to: CurrencyDef, output: Double)
        case mismatch(from: String, to: String)
        case noRate(code: String)
        case unavailable
    }

    static let categoryName = "Currency"

    static func parseConversion(_ tokens: [CalcToken], rates: CurrencyRates?) -> ConversionParse? {
        let tokens = amountFirst(tokens)
        guard tokens.count >= 3, CalcUnits.isConnector(tokens[tokens.count - 2]),
            case .ident(let toName) = tokens[tokens.count - 1],
            case .ident(let fromName) = tokens[tokens.count - 3]
        else { return nil }

        switch (byName[fromName], byName[toName]) {
        case (nil, nil):
            return nil
        case (.some, nil):
            guard let to = CalcUnits.byName[toName] else { return nil }
            return .mismatch(from: categoryName, to: to.category.displayName)
        case (nil, .some):
            guard let from = CalcUnits.byName[fromName] else { return nil }
            return .mismatch(from: from.category.displayName, to: categoryName)
        case (let from?, let to?):
            let valueTokens = Array(tokens[0..<(tokens.count - 3)])
            let input: Double
            if valueTokens.isEmpty {
                input = 1
            } else if let value = CalcExpressionParser.scalar(valueTokens) {
                input = value
            } else {
                return nil
            }

            guard let rates else { return .unavailable }
            guard rates.rate(for: from.code) != nil else { return .noRate(code: from.code) }
            guard rates.rate(for: to.code) != nil else { return .noRate(code: to.code) }
            guard let output = rates.convert(input, from: from.code, to: to.code) else {
                return .noRate(code: to.code)
            }
            return .value(input: input, from: from, to: to, output: output)
        }
    }

    private static func amountFirst(_ tokens: [CalcToken]) -> [CalcToken] {
        guard tokens.count >= 2, case .ident(let name) = tokens[0], byName[name] != nil,
            numberToken(tokens[1])
        else { return tokens }
        var reordered = tokens
        reordered.swapAt(0, 1)
        return reordered
    }

    private static func numberToken(_ token: CalcToken) -> Bool {
        switch token {
        case .number, .compactNumber:
            return true
        default:
            return false
        }
    }

    /// Hand-written because CLDR won't assign a shared noun. docs/features/calculator.md
    private static let contested: [String: [String]] = [
        "USD": ["dollar", "dollars"],
        "CHF": ["franc", "francs"],
        "GBP": ["pound", "pounds"],
        "MXN": ["peso", "pesos"],
        "INR": ["rupee", "rupees"],
        "KES": ["shilling", "shillings"],
        "AED": ["dirham", "dirhams"],
        "KRW": ["won"],
        "RON": ["leu", "lei"],
        "RUB": ["ruble", "rubles"],
        "SAR": ["riyal", "riyals"]
    ]

    /// ISO 4217's own names where CLDR differs; the standard is the source of truth.
    private static let isoNames: [String: [String]] = [
        "CNY": ["rmb", "renminbi"]
    ]

    /// Codes daily use spells from CLDR's sign, not ISO 4217. docs/features/calculator.md
    private static let signCodes: [String: [String]] = [
        "TWD": ["ntd"]
    ]

    static let crypto: [(code: String, name: String, aliases: [String])] = [
        ("ADA", "Cardano", ["cardano"]),
        ("AVAX", "Avalanche", ["avalanche"]),
        ("BCH", "Bitcoin Cash", []),
        ("BNB", "BNB", ["binance"]),
        ("BSV", "Bitcoin SV", []),
        ("BTC", "Bitcoin", ["bitcoin"]),
        ("DASH", "Dash", []),
        ("DOGE", "Dogecoin", ["dogecoin"]),
        ("DOT", "Polkadot", ["polkadot"]),
        ("EOS", "EOS", []),
        ("ETC", "Ethereum Classic", []),
        ("ETH", "Ethereum", ["ethereum", "ether"]),
        ("LTC", "Litecoin", ["litecoin"]),
        ("LUNA", "Terra", ["terra"]),
        ("NEO", "Neo", []),
        ("POL", "Polygon", ["polygon"]),
        ("SHIB", "Shiba Inu", ["shiba"]),
        ("SOL", "Solana", ["solana"]),
        ("TRX", "TRON", ["tron"]),
        ("USDT", "Tether", ["tether"]),
        ("XLM", "Stellar", ["stellar"]),
        ("XMR", "Monero", ["monero"]),
        ("XRP", "XRP", ["ripple"])
    ]

    static let cryptoCodes: [String] = crypto.map(\.code)

    static let byName: [String: CurrencyDef] = {
        var defs: [String: CurrencyDef] = [:]
        var table: [String: CurrencyDef] = [:]
        defs.reserveCapacity(CurrencyData.all.count + crypto.count)
        table.reserveCapacity(CurrencyData.all.count + CurrencyData.aliases.count + crypto.count)
        for entry in CurrencyData.all {
            let def = CurrencyDef(code: entry.code, name: entry.name)
            defs[entry.code] = def
            table[entry.code.lowercased()] = def
        }
        for (word, code) in CurrencyData.aliases { table[word] = defs[code] }
        for entry in crypto {
            let def = CurrencyDef(code: entry.code, name: entry.name)
            defs[entry.code] = def
            table[entry.code.lowercased()] = def
            for word in entry.aliases { table[word] = def }
        }
        for (code, words) in contested {
            guard let def = defs[code] else { continue }
            for word in words { table[word] = def }
        }
        for (code, words) in isoNames {
            guard let def = defs[code] else { continue }
            for word in words { table[word] = def }
        }
        for (code, words) in signCodes {
            guard let def = defs[code] else { continue }
            for word in words { table[word] = def }
        }
        return table
    }()
}
