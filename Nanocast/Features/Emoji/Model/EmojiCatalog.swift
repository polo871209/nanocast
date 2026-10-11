import Foundation

enum EmojiCategory: String, CaseIterable, Sendable {
    case smileysAndPeople = "sp"
    case animalsAndNature = "an"
    case foodAndDrink = "fd"
    case activity = "ac"
    case travelAndPlaces = "tp"
    case objects = "ob"
    case symbols = "sy"
    case flags = "fl"
    case arrows = "xa"
    case currency = "xc"
    case math = "xm"
    case shapesAndPunctuation = "xs"
    case cjk = "xj"
    case keysAndTechnical = "xk"

    var title: String {
        switch self {
        case .smileysAndPeople: return "Smileys & People"
        case .animalsAndNature: return "Animals & Nature"
        case .foodAndDrink: return "Food & Drink"
        case .activity: return "Activity"
        case .travelAndPlaces: return "Travel & Places"
        case .objects: return "Objects"
        case .symbols: return "Symbols"
        case .flags: return "Flags"
        case .arrows: return "Arrows"
        case .currency: return "Currency"
        case .math: return "Math"
        case .shapesAndPunctuation: return "Shapes & Punctuation"
        case .cjk: return "CJK Symbols"
        case .keysAndTechnical: return "Keys & Technical"
        }
    }

    var systemImage: String {
        switch self {
        case .smileysAndPeople: "face.smiling"
        case .animalsAndNature: "pawprint"
        case .foodAndDrink: "pizza.slice"
        case .activity: "gamecontroller"
        case .travelAndPlaces: "paperplane"
        case .objects: "lightbulb"
        case .symbols: "number.sign"
        case .flags: "flag"
        case .arrows: "arrow.up.right"
        case .currency: "dollarsign"
        case .math: "squareroot"
        case .shapesAndPunctuation: "triangle"
        case .cjk: "globe"
        case .keysAndTechnical: "command"
        }
    }

    var itemTitle: String {
        switch self {
        case .symbols, .arrows, .currency, .math, .shapesAndPunctuation, .cjk,
            .keysAndTechnical:
            "Symbol"
        default:
            "Emoji"
        }
    }
}

enum EmojiCategoryFilter: Hashable, Sendable {
    case all
    case pinned
    case frequentlyUsed
    case category(EmojiCategory)

    static let allCases: [Self] =
        [.all, .pinned, .frequentlyUsed] + EmojiCategory.allCases.map(Self.category)

    var title: String {
        switch self {
        case .all: "All Categories"
        case .pinned: "Pinned"
        case .frequentlyUsed: "Frequently Used"
        case .category(let category): category.title
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.3x3.square"
        case .pinned: "pin"
        case .frequentlyUsed: "clock"
        case .category(let category): category.systemImage
        }
    }
}

enum EmojiGridZoom: Sendable {
    case actualSize
    case zoomIn
    case zoomOut
}

enum EmojiGridColumns: Int, CaseIterable, Identifiable, Sendable {
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10

    static let `default`: Self = .eight

    var id: Int { rawValue }

    func applying(_ zoom: EmojiGridZoom, default defaultColumns: Self) -> Self? {
        let next: Self? =
            switch zoom {
            case .actualSize: defaultColumns
            case .zoomIn: Self(rawValue: rawValue - 1)
            case .zoomOut: Self(rawValue: rawValue + 1)
            }
        return next == self ? nil : next
    }
}

enum EmojiSkinTone: String, CaseIterable, Identifiable, Sendable {
    case none, light, mediumLight, medium, mediumDark, dark

    var id: String { rawValue }

    var modifier: Unicode.Scalar? {
        switch self {
        case .none: return nil
        case .light: return Unicode.Scalar(0x1F3FB)
        case .mediumLight: return Unicode.Scalar(0x1F3FC)
        case .medium: return Unicode.Scalar(0x1F3FD)
        case .mediumDark: return Unicode.Scalar(0x1F3FE)
        case .dark: return Unicode.Scalar(0x1F3FF)
        }
    }

    var title: String {
        switch self {
        case .none: return "Default"
        case .light: return "Light"
        case .mediumLight: return "Medium Light"
        case .medium: return "Medium"
        case .mediumDark: return "Medium Dark"
        case .dark: return "Dark"
        }
    }

    var sample: String { EmojiCatalog.applyTone(self, to: "👋") }
}

struct EmojiEntry: Identifiable, Hashable, Sendable {
    let glyph: String
    let name: String
    let category: EmojiCategory
    let supportsSkinTone: Bool
    let keywords: String

    var id: String { glyph }
    var displayName: String { name.capitalized }

    func display(tone: EmojiSkinTone) -> String {
        guard supportsSkinTone, tone != .none else { return glyph }
        return EmojiCatalog.applyTone(tone, to: glyph)
    }
}

enum EmojiCatalog {
    static func applyTone(_ tone: EmojiSkinTone, to glyph: String) -> String {
        guard let modifier = tone.modifier else { return glyph }
        var scalars = String.UnicodeScalarView(glyph.unicodeScalars.filter { $0.value != 0xFE0F })
        scalars.append(modifier)
        return String(scalars)
    }

    nonisolated static func parse(_ raw: String) -> [EmojiEntry] {
        var result: [EmojiEntry] = []
        result.reserveCapacity(2200)
        for line in raw.split(separator: "\n") {
            let fields = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5, let category = EmojiCategory(rawValue: String(fields[2]))
            else { continue }
            result.append(
                EmojiEntry(
                    glyph: String(fields[0]), name: String(fields[1]), category: category,
                    supportsSkinTone: fields[3] == "1", keywords: String(fields[4])))
        }
        return result
    }
}
