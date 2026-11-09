import SwiftUI

struct ScreenRecordingView: View {
    let session: ScreenRecordingSession
    let metrics: InterfaceMetrics
    let record: () -> Void
    let pause: () -> Void
    let stop: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            Circle()
                .fill(isLive ? Theme.Colors.destructive : Theme.Colors.textTertiary)
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
            primaryButton
            ScreenshotToolbarButton(
                symbol: "stop.fill", title: "Stop and save", tint: Theme.Colors.destructive,
                isEnabled: canStop, action: stop)
        }
        .padding(metrics.spacing.xs)
        .screenshotChrome(metrics)
        .accessibilityLabel("Screen recording")
    }

    private var isLive: Bool {
        if case .recording = session.status { true } else { false }
    }

    private var canStop: Bool {
        switch session.status {
        case .starting, .recording, .paused: true
        case .ready, .saving: false
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch session.status {
        case .ready:
            ScreenshotToolbarButton(
                symbol: "record.circle", title: "Start recording", tint: Theme.Colors.destructive, action: record)
        case .paused:
            ScreenshotToolbarButton(
                symbol: "record.circle", title: "Resume recording", tint: Theme.Colors.destructive, action: record)
        case .starting, .recording, .saving:
            ScreenshotToolbarButton(symbol: "pause.fill", title: "Pause", isEnabled: isLive, action: pause)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch session.status {
        case .ready: Text("Ready")
        case .starting: Text("Starting…")
        case .recording(let since): Text(timerInterval: since...Date.distantFuture, countsDown: false)
        case .paused(let recorded): Text(Duration.seconds(recorded).formatted(.time(pattern: .minuteSecond)))
        case .saving: Text("Saving…")
        }
    }
}
