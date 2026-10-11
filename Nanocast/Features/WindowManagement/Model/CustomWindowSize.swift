import CoreGraphics
import Foundation

struct CustomWindowSize: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "window-size:"
    static let sfSymbol = "macwindow.and.cursorarrow"

    struct Dimension: Codable, Hashable, Sendable {
        enum Unit: String, Codable, CaseIterable, Sendable {
            case points
            case percent

            var range: ClosedRange<Int> {
                switch self {
                case .points: return 1...16_000
                case .percent: return 1...100
                }
            }

            var suffix: String {
                switch self {
                case .points: return "pt"
                case .percent: return "%"
                }
            }
        }

        var value: Int
        var unit: Unit

        init(_ value: Int, _ unit: Unit) {
            self.value = value.clamped(to: unit.range)
            self.unit = unit
        }

        var label: String {
            unit == .points ? "\(value) pt" : "\(value)%"
        }

        func length(in available: CGFloat) -> CGFloat {
            let requested =
                unit == .points ? CGFloat(value) : available * CGFloat(value) / 100
            return min(available, max(WindowLayoutGeometry.minimumLength, requested))
        }

        func converted(to unit: Unit, in available: CGFloat) -> Dimension {
            guard unit != self.unit, available > 0 else { return Dimension(value, unit) }
            let points = unit == .percent ? CGFloat(value) : CGFloat(value) * available / 100
            let converted = unit == .percent ? points / available * 100 : points
            return Dimension(Int(converted.rounded()), unit)
        }
    }

    struct Offset: Codable, Hashable, Sendable {
        static let range: ClosedRange<Int> = -4000...4000
        static let zero = Offset(x: 0, y: 0)

        var x: Int
        var y: Int

        init(x: Int, y: Int) {
            self.x = x.clamped(to: Self.range)
            self.y = y.clamped(to: Self.range)
        }
    }

    let id: UUID
    var name: String
    var width: Dimension
    var height: Dimension
    var anchor: WindowLayoutAnchor
    var offset: Offset

    init(
        id: UUID = UUID(), name: String, width: Dimension = Dimension(60, .percent),
        height: Dimension = Dimension(60, .percent), anchor: WindowLayoutAnchor = .center,
        offset: Offset = .zero
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.anchor = anchor
        self.offset = offset
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, width, height, anchor, offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        width = try container.decode(Dimension.self, forKey: .width)
        height = try container.decode(Dimension.self, forKey: .height)
        anchor = try container.decode(WindowLayoutAnchor.self, forKey: .anchor)
        offset = try container.decodeIfPresent(Offset.self, forKey: .offset) ?? .zero
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    var summary: String {
        let base = "\(width.label) × \(height.label) · \(anchor.title)"
        return offset == .zero ? base : "\(base) · Offset \(offset.x), \(offset.y) pt"
    }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        guard order == .orderedSame else { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    var sanitized: CustomWindowSize {
        var cleaned = self
        cleaned.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.width = Dimension(width.value, width.unit)
        cleaned.height = Dimension(height.value, height.unit)
        cleaned.offset = Offset(x: offset.x, y: offset.y)
        return cleaned
    }

    func frame(in visibleFrame: CGRect, gap: CGFloat) -> CGRect? {
        let canvas = WindowPlacementEngine.canvas(
            visibleFrame, gap: WindowPlacementEngine.sanitizedGap(gap, in: visibleFrame))
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let size = CGSize(
            width: width.length(in: canvas.width), height: height.length(in: canvas.height))
        let placed = anchor.placement.place(size, in: canvas)
            .offsetBy(dx: CGFloat(offset.x), dy: CGFloat(offset.y))
        return WindowPlacementEngine.rounded(WindowPlacementEngine.clamped(placed, into: canvas))
    }

    func placement(
        for windowFrame: CGRect, screens: [WindowPlacementEngine.Screen], gap: CGFloat
    ) -> WindowPlacementEngine.Placement? {
        guard let host = WindowPlacementEngine.screen(containing: windowFrame, in: screens),
            let frame = frame(in: host.visibleFrame, gap: gap)
        else { return nil }
        return WindowPlacementEngine.Placement(
            frame: frame, screenID: host.id, anchor: anchor.placement, resizes: true)
    }
}

enum CustomWindowSizeValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case invalidCharacter

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the size."
        case .duplicateName: return "A custom size with this name already exists."
        case .invalidCharacter: return "Names cannot contain null characters."
        }
    }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
