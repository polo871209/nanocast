import SwiftUI

extension AppCore {
    var calcNumberFormat: CalcNumberFormat { regionNumberFormat.format(for: settings.calcNumberStyle) }
}

@MainActor
enum CalcMemo {
    private struct Cache {
        let query: String
        let stamp: Date?
        let region: String?
        let format: CalcNumberFormat
        let result: CalcResult?
    }

    private static var cache: Cache?

    static func evaluate(_ query: String, rates: CurrencyRates?, format: CalcNumberFormat) -> CalcResult? {
        let region = RegionCurrency.code
        if let cache, cache.query == query, cache.stamp == rates?.fetchedAt, cache.region == region,
            cache.format == format
        {
            return cache.result
        }
        let result = CalcEngine.evaluate(
            query, now: Date(), calendar: .current, rates: rates, region: region, format: format)
        cache = Cache(query: query, stamp: rates?.fetchedAt, region: region, format: format, result: result)
        return result
    }
}

struct CalculatorCard: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppCore.self) private var core
    let result: CalcResult
    let selected: Bool

    var body: some View {
        let result = core.calcNumberFormat.localized(result)
        return Group {
            switch result.payload {
            case .value(let display, _):
                HStack(spacing: 0) {
                    LeadCardColumn(
                        text: CalcSyntax.highlighted(result.expression),
                        badge: result.sourceBadge)
                    Image(systemName: "arrow.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    LeadCardColumn(
                        text: CalcSyntax.highlighted(display), badge: result.targetBadge,
                        weight: .semibold)
                }
                .fixedSize(horizontal: false, vertical: true)
            case .error(let message):
                HStack(spacing: metrics.spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .symbolRenderingMode(.hierarchical)
                    Text(message)
                        .lineLimit(1)
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xxxl)
        .leadCard(selected: selected)
    }
}

private enum CalcSyntax {
    static func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString()
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in words.enumerated() {
            if index > 0 { attributed.append(AttributedString(" ")) }
            var piece = AttributedString(String(word))
            if isConnector(word, at: index, of: words) {
                piece.foregroundColor = Theme.Colors.textTertiary
            }
            attributed.append(piece)
        }
        return attributed
    }

    private static func isConnector(
        _ word: Substring, at index: Int, of words: [Substring]
    ) -> Bool {
        let lowered = word.lowercased()
        if connectors.contains(lowered) { return true }
        guard lowered == "in", index > 0, index + 1 < words.count else { return false }
        return words[index + 1].lowercased() != "in"
    }

    private static let connectors: Set<String> = [
        "to", "of", "off", "on", "as", "from", "ago", "at", "tip", "ratio", "average", "avg",
        "mean", "sum", "total", "round", "nearest", "and", "is", "what", "the", "next", "last",
        "+", "-", "×", "÷", "^", "→", "->", "mod"
    ]
}

@MainActor
enum CalcActionsMenu {
    static func content(result: CalcResult, core: AppCore) -> PopoverMenuContent {
        var items = [
            PopoverMenuItem(
                title: String(localized: "Copy Answer"), systemImage: "doc.on.doc", shortcut: "↵"
            ) {
                core.calculatorCoordinator.copyCalculatorResult(result)
            }
        ]
        if result.canChain {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Put Answer in Search Bar"), systemImage: "text.cursor",
                    shortcut: "⌘↵"
                ) {
                    core.calculatorCoordinator.putAnswerInSearchBar(result)
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Copy Calculation"), systemImage: "doc.on.doc.fill",
                shortcut: "⇧⌘↵"
            ) {
                core.calculatorCoordinator.copyCalculationWithExpression(result)
            })
        return PopoverMenuContent(
            header: core.calcNumberFormat.localizedExpression(result.expression), items: items)
    }
}
