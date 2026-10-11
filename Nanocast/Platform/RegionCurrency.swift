import Foundation

enum RegionCurrency {
    static var code: String? { Locale.current.currency?.identifier }
}
