import SwiftUI

struct ScrollCaptureView: View {
    let session: ScrollCaptureSession
    let metrics: InterfaceMetrics
    let toggleScrolling: () -> Void
    let done: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            Text(status)
                .font(metrics.typography.keyCap.monospacedDigit())
                .foregroundStyle(isWarning ? Theme.Colors.warning : Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: metrics.scaled(Theme.Markup.scrollStatusWidth))
            ScreenshotToolbarDivider()
            ScreenshotToolbarButton(
                symbol: session.status == .scrolling ? "stop.fill" : "play.fill",
                title: session.status == .scrolling ? "Stop scrolling  Space" : "Start scrolling  Space",
                isEnabled: session.status != .full, action: toggleScrolling)
            ScreenshotToolbarButton(symbol: "xmark", title: "Discard", tint: Theme.Colors.destructive, action: discard)
            ScreenshotToolbarButton(
                symbol: "checkmark", title: "Edit the long image  ↩ or Esc", tint: Theme.Colors.success, action: done)
        }
        .padding(metrics.spacing.xs)
        .screenshotChrome(metrics)
        .accessibilityLabel("Scrolling capture")
    }

    private var status: String {
        switch session.status {
        case .ready: return "Ready to scroll"
        case .scrolling, .stopped, .finished: return "\(session.pointWidth) × \(session.pointHeight.formatted())"
        case .lost: return "Lost the page"
        case .full: return "Height limit"
        }
    }

    private var isWarning: Bool {
        [.lost, .full].contains(session.status)
    }
}
