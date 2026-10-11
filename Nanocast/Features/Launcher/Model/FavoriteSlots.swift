import Foundation

enum FavoriteSlots {
    static let digits: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    private static let numberRowKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]

    static func index(for digit: Character) -> Int? { digits.firstIndex(of: digit) }

    static func index(forKeyCode keyCode: UInt16) -> Int? {
        numberRowKeyCodes.firstIndex(of: keyCode)
    }

    static func digit(at index: Int) -> Character? {
        digits.indices.contains(index) ? digits[index] : nil
    }
}
