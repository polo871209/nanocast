import Foundation

enum PaletteShortcut: Equatable {
    case commandDelete
    case delete
    case deleteAll
    case copyFile
    case copyName
    case copyPath
    case copyText
    case copyCalculation
    case pasteFile
    case quickLook
    case toggleFavorite
    case hideFromSearch
    case quit
    case forceQuit
    case minimizeWindow
    case hideApp
    case restart
    case newItem
    case edit
    case duplicate
    case showInFinder
    case settings
    /// ⌘., which AppKit binds to `cancelOperation:`, so it arrives as a token instead of a key.
    case pin
    case favoriteSlot(Int)

    static func resolve(
        command: Bool, shift: Bool, option: Bool, control: Bool, isDeleteKey: Bool,
        matches: (Character) -> Bool
    ) -> Self? {
        if isDeleteKey { return command ? .commandDelete : nil }
        if command, matches("c") {
            if shift { return .copyFile }
            if option { return .copyName }
            return control ? .copyPath : nil
        }
        if command, shift, matches("v") { return .pasteFile }
        if command, shift, matches("t") { return .copyText }
        if command, matches("y") { return .quickLook }
        if control, matches("x") { return shift ? .deleteAll : .delete }
        if command, matches("f") { return shift ? .toggleFavorite : .showInFinder }
        if command, shift, matches("h") { return .hideFromSearch }
        if control, shift, matches("q") { return option ? .forceQuit : .quit }
        if control, shift, matches("m") { return .minimizeWindow }
        if control, shift, matches("h") { return .hideApp }
        if command, matches("r") { return .restart }
        if command, !shift, matches("n") { return .newItem }
        if command, !shift, !option, !control, matches("e") { return .edit }
        if command, !shift, matches("d") { return .duplicate }
        if command, option, matches(",") { return .settings }
        return nil
    }

    var requiresExpanded: Bool {
        switch self {
        case .copyFile, .copyName, .copyPath, .copyText, .pasteFile, .quickLook, .toggleFavorite,
            .hideFromSearch, .quit, .forceQuit, .minimizeWindow, .hideApp, .restart, .edit, .duplicate,
            .showInFinder:
            true
        case .commandDelete, .delete, .deleteAll, .pin, .favoriteSlot, .newItem,
            .settings, .copyCalculation:
            false
        }
    }

    var closesMenu: Bool {
        switch self {
        case .delete, .deleteAll, .copyFile, .copyName, .copyPath, .copyText, .copyCalculation,
            .quickLook, .toggleFavorite, .hideFromSearch, .minimizeWindow, .newItem, .settings, .edit,
            .duplicate, .showInFinder:
            true
        case .commandDelete, .pasteFile, .quit, .forceQuit, .hideApp, .restart, .pin, .favoriteSlot:
            false
        }
    }
}
