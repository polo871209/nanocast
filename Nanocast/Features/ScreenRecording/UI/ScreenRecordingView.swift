import SwiftUI

struct ScreenRecordingView: View {
    let session: ScreenRecordingSession
    let metrics: InterfaceMetrics
    let stop: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            Circle()
                .fill(Theme.Colors.destructive)
                .frame(width: metrics.scaled(Theme.Markup.recordingDot), height: metrics.scaled(Theme.Markup.recordingDot))
                .padding(.leading, metrics.spacing.xs)
                .accessibilityHidden(true)
            status
                .font(metrics.typography.keyCap.monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: metrics.scaled(Theme.Markup.recordingStatusWidth))
            ScreenshotToolbarDivider()
            ScreenshotToolbarButton(
                symbol: "xmark", title: "Discard", tint: Theme.Colors.destructive,
                isEnabled: session.status != .saving, action: discard)
            ScreenshotToolbarButton(
                symbol: "stop.fill", title: "Stop and save", tint: Theme.Colors.destructive,
                isEnabled: session.status != .saving, action: stop)
        }
        .padding(metrics.spacing.xs)
        .screenshotChrome(metrics)
        .accessibilityLabel("Screen recording")
    }

    @ViewBuilder
    private var status: some View {
        switch session.status {
        case .starting: Text("Starting…")
        case .recording(let since): Text(timerInterval: since...Date.distantFuture, countsDown: false)
        case .saving: Text("Saving…")
        }
    }
}
