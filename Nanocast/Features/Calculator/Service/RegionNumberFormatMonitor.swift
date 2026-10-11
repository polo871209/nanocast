import Foundation

@MainActor
@Observable
final class RegionNumberFormatMonitor {
    private(set) var system = RegionNumberFormatMonitor.read()
    @ObservationIgnored private var token: NotificationCenter.ObservationToken?

    init() {
        token = NotificationCenter.default.addObserver(of: Locale.self, for: .currentLocaleDidChange) { [weak self] _ in
            self?.system = Self.read()
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    func format(for style: CalcNumberStyle) -> CalcNumberFormat {
        style == .system ? system : .english
    }

    private static func read() -> CalcNumberFormat {
        let locale = Locale.autoupdatingCurrent
        return CalcNumberFormat(
            decimalSeparator: locale.decimalSeparator ?? ".", groupingSeparator: locale.groupingSeparator)
            ?? .english
    }
}
