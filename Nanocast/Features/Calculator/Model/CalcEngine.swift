import Foundation

struct CalcResult: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case value(display: String, copyText: String)
        case error(message: String)

        static func number(_ value: Double, suffix: String = "") -> Self {
            let text = CalcFormatter.copyText(value)
            return .value(display: CalcFormatter.grouped(text) + suffix, copyText: text + suffix)
        }

        static func measurement(_ value: Double, unit: UnitDef) -> Self {
            let text = CalcFormatter.copyText(value)
            let copySeparator = unit.category == .pixels ? "" : " "
            return .value(
                display: "\(CalcFormatter.grouped(text)) \(unit.symbol)",
                copyText: text + copySeparator + unit.symbol)
        }
    }

    let expression: String
    let sourceBadge: String?
    let targetBadge: String?
    let payload: Payload
    let canChain: Bool

    init(
        expression: String, sourceBadge: String? = nil, targetBadge: String? = nil, payload: Payload,
        canChain: Bool = true
    ) {
        self.expression = expression
        self.sourceBadge = sourceBadge
        self.targetBadge = targetBadge
        self.payload = payload
        self.canChain = canChain
    }

    var isActionable: Bool {
        if case .value = payload { return true }
        return false
    }
}

enum CalcEngine {
    static func evaluate(
        _ raw: String, now: Date, calendar: Calendar, rates: CurrencyRates? = nil,
        region: String? = nil, format: CalcNumberFormat = .english
    ) -> CalcResult? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 256, let query = format.canonical(trimmed) else {
            return nil
        }
        if query.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) {
            return CalcDateTime.namedMoment(query, now: now, calendar: calendar).map(unchained)
        }

        if let dateTime = CalcDateTime.evaluate(query, now: now, calendar: calendar) {
            return unchained(dateTime)
        }

        if let zone = CalcTimeZone.evaluate(query, now: now, calendar: calendar) {
            return unchained(zone)
        }

        guard let tokens = CalcTokenizer.tokenize(query), !tokens.isEmpty else { return nil }

        if let partial = partialResult(
            tokens, query: query, now: now, calendar: calendar, rates: rates, region: region)
        {
            return partial
        }

        if tokens.count == 1 {
            if case .intLiteral(let value, let base) = tokens[0], base != .decimal {
                let display = CalcFormatter.grouped(String(value))
                return CalcResult(
                    expression: query,
                    sourceBadge: base.name, targetBadge: "Decimal",
                    payload: .value(display: display, copyText: String(value)))
            }
            if case .compactNumber(let value) = tokens[0] {
                return CalcResult(
                    expression: query,
                    sourceBadge: "Expression", targetBadge: "Result",
                    payload: .number(value))
            }
            return nil
        }

        if let base = baseConversion(tokens, query: query) { return base }

        if let quantity = CalcQuantity.evaluate(tokens, query: query, rates: rates, region: region) {
            return quantity
        }

        if let conversion = CalcUnits.parseConversion(tokens) ?? CalcUnits.parseUnitPairConversion(tokens) {
            switch conversion {
            case .value(let input, let from, let to, let output):
                return CalcResult(
                    expression: "\(CalcFormatter.display(input)) \(from.symbol)",
                    sourceBadge: from.name,
                    targetBadge: to.name,
                    payload: .measurement(output, unit: to))
            case .mismatch(let from, let to):
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message: "Cannot convert \(from.category.displayName) to \(to.category.displayName)."))
            }
        }

        if let conversion = CalcCurrency.parseConversion(tokens, rates: rates) {
            switch conversion {
            case .value(let input, let from, let to, let output):
                let amount = CalcFormatter.currency(output)
                return CalcResult(
                    expression: "\(CalcFormatter.display(input)) \(from.code)",
                    sourceBadge: from.name,
                    targetBadge: to.name,
                    payload: .value(
                        display: "\(CalcFormatter.grouped(amount)) \(to.code)",
                        copyText: "\(amount) \(to.code)"))
            case .mismatch(let from, let to):
                return CalcResult(
                    expression: query,
                    payload: .error(message: "Cannot convert \(from) to \(to)."))
            case .noRate(let code):
                return CalcResult(
                    expression: query,
                    payload: .error(message: "No exchange rate for \(code)."))
            case .unavailable:
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message: "Exchange rates unavailable — check your connection."))
            }
        }

        if let bare = CalcUnits.parseBareConversion(tokens) {
            let payload: CalcResult.Payload
            if bare.compound {
                let text = CalcFormatter.compoundFeetInches(bare.output)
                payload = .value(display: text, copyText: text)
            } else {
                payload = .measurement(bare.output, unit: bare.to)
            }
            return CalcResult(
                expression: "\(CalcFormatter.display(bare.input)) \(bare.from.symbol)",
                sourceBadge: bare.from.name,
                targetBadge: bare.to.name,
                payload: payload)
        }

        if let percent = CalcPercent.evaluate(tokens, query: query) { return percent }

        return nil
    }

    private static func partialResult(
        _ tokens: [CalcToken], query: String, now: Date, calendar: Calendar,
        rates: CurrencyRates?, region: String?
    ) -> CalcResult? {
        guard let trailing = tokens.last, let operatorText = partialOperatorText(trailing) else {
            return nil
        }
        let prefixTokens = Array(tokens.dropLast())
        guard !prefixTokens.isEmpty else { return nil }
        if prefixTokens.count == 1, let value = decimalLiteral(prefixTokens[0]) {
            return CalcResult(
                expression: CalcFormatter.expression(query),
                sourceBadge: "Expression", targetBadge: "Result",
                payload: .number(value))
        }

        if let quantity = CalcQuantity.evaluate(
            prefixTokens, query: tokenQuery(prefixTokens), rates: rates, region: region,
            preserveStandaloneUnit: true)
        {
            return replacingExpression(
                quantity, with: "\(quantity.expression) \(operatorText)")
        }

        if let complete = evaluate(
            tokenQuery(prefixTokens), now: now, calendar: calendar, rates: rates, region: region)
        {
            return replacingExpression(complete, with: CalcFormatter.expression(query))
        }

        guard let value = CalcExpressionParser.scalar(prefixTokens) else { return nil }
        return CalcResult(
            expression: CalcFormatter.expression(query),
            sourceBadge: "Expression", targetBadge: "Result",
            payload: .number(value))
    }

    private static func partialOperatorText(_ token: CalcToken) -> String? {
        guard case .op(let op) = token else { return nil }
        switch op {
        case .multiply: return "×"
        case .divide: return "÷"
        case .add, .subtract, .power: return String(op.rawValue)
        default: return nil
        }
    }

    private static func tokenQuery(_ tokens: [CalcToken]) -> String {
        tokens.map { token in
            switch token {
            case .number(let value), .compactNumber(let value):
                if let integer = Int64(exactly: value) { return String(integer) }
                return String(value)
            case .intLiteral(let value, let base):
                return base.prefix + String(value, radix: base.rawValue)
            case .ident(let name):
                return name
            case .op(let op):
                return op.text
            case .arrow:
                return "->"
            case .comma:
                return ","
            }
        }.joined(separator: " ")
    }

    private static func replacingExpression(_ result: CalcResult, with expression: String) -> CalcResult {
        CalcResult(
            expression: expression,
            sourceBadge: result.sourceBadge,
            targetBadge: result.targetBadge,
            payload: result.payload,
            canChain: result.canChain)
    }

    private static func unchained(_ result: CalcResult) -> CalcResult {
        CalcResult(
            expression: result.expression,
            sourceBadge: result.sourceBadge,
            targetBadge: result.targetBadge,
            payload: result.payload,
            canChain: false)
    }

    private static func baseConversion(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 3, CalcUnits.isConnector(tokens[tokens.count - 2]),
            case .ident(let name) = tokens[tokens.count - 1], let target = CalcNumberBase(name: name)
        else { return nil }

        let valueTokens = Array(tokens[0..<(tokens.count - 2)])
        let literalText = query.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? query
        let source: UInt64
        let sourceBadge: String
        let sourceText: String
        if valueTokens.count == 1, case .intLiteral(let value, let base) = valueTokens[0] {
            source = value
            sourceBadge = base.name
            sourceText = literalText
        } else if valueTokens.count == 1, let value = decimalLiteral(valueTokens[0]),
            value >= 0, value.rounded() == value, value <= 9_007_199_254_740_992
        {
            source = UInt64(value)
            sourceBadge = "Decimal"
            sourceText = literalText
        } else if let value = CalcExpressionParser.scalar(valueTokens),
            value >= 0, value.rounded() == value, value <= 9_007_199_254_740_992
        {
            source = UInt64(value)
            sourceBadge = "Decimal"
            sourceText = CalcFormatter.grouped(String(source))
        } else {
            return nil
        }

        let output =
            target == .decimal
            ? CalcFormatter.grouped(String(source))
            : target.prefix + String(source, radix: target.rawValue, uppercase: true)
        return CalcResult(
            expression: sourceText,
            sourceBadge: sourceBadge,
            targetBadge: target.name,
            payload: .value(
                display: output, copyText: output.replacingOccurrences(of: ",", with: "")))
    }

    private static func decimalLiteral(_ token: CalcToken) -> Double? {
        switch token {
        case .number(let value), .compactNumber(let value): return value
        default: return nil
        }
    }

}
