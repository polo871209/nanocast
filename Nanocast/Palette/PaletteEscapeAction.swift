import Foundation

enum PaletteEscapeAction: Equatable {
    case clearMenuQuery
    case closeMenu
    case leaveArgumentField
    case clearQuery
    case goBack
    case hidePalette

    static func resolve(
        menuOpen: Bool, menuQuery: String, argumentFocused: Bool, query: String, canGoBack: Bool,
        behavior: EscapeKeyBehavior
    ) -> Self {
        if menuOpen { return menu(query: menuQuery) }
        if argumentFocused { return .leaveArgumentField }
        if !query.isEmpty { return .clearQuery }
        guard behavior == .navigateBackOrClose else { return .hidePalette }
        return canGoBack ? .goBack : .hidePalette
    }

    static func menu(query: String) -> Self {
        query.isEmpty ? .closeMenu : .clearMenuQuery
    }
}
