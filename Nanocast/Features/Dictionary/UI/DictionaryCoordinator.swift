import Foundation

@MainActor
final class DictionaryCoordinator {
    private let paletteCoordinator: PaletteCoordinator

    init(paletteCoordinator: PaletteCoordinator) {
        self.paletteCoordinator = paletteCoordinator
    }

    func show() {
        paletteCoordinator.togglePalette(mode: .dictionary)
    }

    func copy(_ entry: DictionaryEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.text)
    }

    func openInDictionary(_ entry: DictionaryEntry) {
        guard let term = entry.term.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
            let url = URL(string: "dict://" + term)
        else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.open(url)
    }
}
