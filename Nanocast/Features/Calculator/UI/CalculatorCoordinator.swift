import AppKit

@MainActor
final class CalculatorCoordinator {
    private let calcHistory: CalculatorHistoryStore
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(
        calcHistory: CalculatorHistoryStore, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.calcHistory = calcHistory
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func deleteAllHistory() async {
        guard
            await core.confirm(
                title: "Clear calculation history?",
                message: "Every past calculation goes. This can't be undone.",
                symbol: PaletteMode.calculatorHistory.systemImage,
                confirmTitle: "Clear History")
        else { return }
        calcHistory.clearAll()
    }

    private var format: CalcNumberFormat { core.calcNumberFormat }

    func copyCalculatorResult(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        calcHistory.record(expression: result.expression, result: display)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(format.localized(copyText))
    }

    @discardableResult
    func putAnswerInSearchBar(_ result: CalcResult) -> Bool {
        guard case .value(let display, let copyText) = result.payload, result.canChain,
            !core.palette.isComposing
        else { return false }
        calcHistory.record(expression: result.expression, result: display)
        core.palette.rewriteQuery(format.localized(copyText))
        return true
    }

    func copyCalculationWithExpression(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        calcHistory.record(expression: result.expression, result: display)
        paletteCoordinator.hidePalette(restoreFocus: false)
        let format = format
        Paster.copyPlainText(
            "\(format.localizedExpression(result.expression)) = \(format.localized(copyText))")
    }

    func copyHistoryEntry(_ entry: CalcHistoryEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(format.localized(entry.copyText))
    }

    func copyHistoryExpression(_ entry: CalcHistoryEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(format.localizedExpression(entry.expression))
    }
}
