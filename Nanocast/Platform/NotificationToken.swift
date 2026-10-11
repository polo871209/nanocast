import Foundation

final class NotificationToken {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol, center: NotificationCenter) {
        self.token = token
        self.center = center
    }

    deinit {
        center.removeObserver(token)
    }
}
