import SwiftUI

struct ScreenRecordingView: View {
    struct Actions {
        let choose: (RecordingTargetKind) -> Void
        let toggleMicrophone: () -> Void
        let toggleCamera: () -> Void
        let recordOrPause: () -> Void
        let stop: () -> Void
        let discard: () -> Void
        let barMoved: () -> Void
    }

    let session: ScreenRecordingSession
    let metrics: InterfaceMetrics
    let actions: Actions

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            SymbolImage(name: "line.3.horizontal", size: metrics.scaled(Theme.Size.noteGlyph))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: metrics.scaled(Theme.Size.noteGlyph), height: metrics.size.barButtonHeight)
                .windowDraggable(true, onEnded: actions.barMoved)
                .accessibilityLabel("Move the bar")
                .tooltip("Drag to move")
            ScreenshotToolbarDivider()
            ForEach(RecordingTargetKind.allCases) { kind in
                ScreenshotToolbarButton(
                    symbol: kind.symbol, title: kind.title, isSelected: kind.matches(session.target),
                    isEnabled: isSetup
                ) { actions.choose(kind) }
            }
            ScreenshotToolbarDivider()
            ZStack {
                Circle()
                    .fill(Theme.Colors.destructive.opacity(0.35))
                    .scaleEffect(isHearing ? 0.6 + CGFloat(session.microphoneLevel) : 0.001)
                    .animation(.easeOut(duration: 0.12), value: session.microphoneLevel)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                ScreenshotToolbarButton(
                    symbol: session.microphone ? "mic.fill" : "mic.slash",
                    title: session.microphone ? "Turn off the microphone" : "Turn on the microphone",
                    isSelected: session.microphone, action: actions.toggleMicrophone)
            }
            ScreenshotToolbarButton(
                symbol: session.camera ? "person.crop.circle.fill" : "person.crop.circle.badge.xmark",
                title: session.camera ? "Turn off the camera" : "Turn on the camera",
                isSelected: session.camera, isEnabled: !session.isChangingCamera, action: actions.toggleCamera)
            ScreenshotToolbarDivider()
            Circle()
                .fill(isLive ? Theme.Colors.destructive : Theme.Colors.textTertiary)
                .frame(width: metrics.scaled(Theme.Markup.recordingDot), height: metrics.scaled(Theme.Markup.recordingDot))
                .accessibilityHidden(true)
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                Text(Duration.seconds(session.recorded(at: context.date)).formatted(.time(pattern: .minuteSecond)))
                    .font(metrics.typography.keyCap.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .frame(width: metrics.scaled(Theme.Markup.recordingStatusWidth))
            }
            ScreenshotToolbarDivider()
            ScreenshotToolbarButton(
                symbol: session.isCapturing ? "pause.fill" : "record.circle",
                title: recordTitle, tint: session.isCapturing ? Theme.Colors.textPrimary : Theme.Colors.destructive,
                isEnabled: !isSaving, action: actions.recordOrPause)
            ScreenshotToolbarButton(
                symbol: "stop.fill", title: "Stop and save", tint: Theme.Colors.destructive,
                isEnabled: !isSetup && !isSaving, action: actions.stop)
            ScreenshotToolbarButton(
                symbol: "xmark", title: isSetup ? "Cancel" : "Discard", tint: Theme.Colors.destructive,
                isEnabled: !isSaving, action: actions.discard)
        }
        .padding(metrics.spacing.xs)
        .screenshotChrome(metrics)
        .accessibilityLabel("Screen recording")
    }

    private var isSetup: Bool { session.status == .setup }

    private var isSaving: Bool {
        if case .saving = session.status { true } else { false }
    }

    private var isLive: Bool {
        if case .recording = session.status { true } else { false }
    }

    private var isHearing: Bool { isLive && session.microphone }

    private var recordTitle: String {
        switch session.status {
        case .setup: "Start recording"
        case .paused: "Resume recording"
        case .starting, .recording, .saving: "Pause"
        }
    }
}

enum RecordingTargetKind: CaseIterable, Identifiable {
    case display
    case area
    case window

    var id: Self { self }

    var symbol: String {
        switch self {
        case .display: "display"
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        }
    }

    var title: String {
        switch self {
        case .display: "Record the entire desktop"
        case .area: "Choose an area"
        case .window: "Choose a window or desktop"
        }
    }

    func matches(_ target: RecordingTarget) -> Bool {
        switch (self, target) {
        case (.display, .display), (.area, .area), (.window, .window): true
        default: false
        }
    }
}
