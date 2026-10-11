import AppKit

@MainActor
final class AppRecencyMonitor {
    private(set) var order: [pid_t] = []
    private var token: NotificationCenter.ObservationToken?

    isolated deinit {
        stop()
    }

    func start() {
        guard token == nil else { return }
        order = Self.onScreenOrder()
        if let front = NSWorkspace.shared.frontmostApplication { promote(front) }
        let workspace = NSWorkspace.shared
        token = workspace.notificationCenter.addObserver(
            of: workspace, for: .didActivateApplication
        ) { [weak self] message in
            self?.promote(message.application)
        }
    }

    func stop() {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        token = nil
        order = []
    }

    private func promote(_ app: NSRunningApplication) {
        let pid = WindowInventory.owningProcess(of: app).processIdentifier
        order.removeAll { $0 == pid }
        order.insert(pid, at: 0)
    }

    private static func onScreenOrder() -> [pid_t] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var order: [pid_t] = []
        for window in listing {
            guard window[kCGWindowLayer as String] as? Int == 0,
                let pid = window[kCGWindowOwnerPID as String] as? pid_t, !order.contains(pid)
            else { continue }
            order.append(pid)
        }
        return order
    }
}
