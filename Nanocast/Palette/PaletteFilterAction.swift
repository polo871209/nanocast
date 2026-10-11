import Foundation

enum PaletteFilterAction: Equatable {
    case clipboardFilter
    case fileSearchFilter
    case emojiCategory
    case ignored

    static func resolve(collapsed: Bool, mode: PaletteMode) -> Self {
        guard !collapsed else { return .ignored }
        switch mode {
        case .clipboard: return .clipboardFilter
        case .fileSearch: return .fileSearchFilter
        case .emoji: return .emojiCategory
        default: return .ignored
        }
    }
}
