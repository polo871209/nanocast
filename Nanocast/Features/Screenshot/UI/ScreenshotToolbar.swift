import SwiftUI

struct ScreenshotToolbar: View {
    let session: ScreenshotSession
    let metrics: InterfaceMetrics
    let edit: (MarkupCommand) -> Void
    let perform: (ScreenshotIntent) -> Void

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            if session.purpose == .recording {
                recordingButtons
            } else {
                captureButtons
            }
        }
        .padding(metrics.spacing.xs)
        .screenshotChrome(metrics)
        .accessibilityLabel(session.purpose == .recording ? "Recording area" : "Screenshot")
    }

    @ViewBuilder
    private var recordingButtons: some View {
        ScreenshotToolbarButton(
            symbol: session.recordingChoices.microphone ? "mic.fill" : "mic.slash",
            title: session.recordingChoices.microphone ? "Microphone on  M" : "Microphone off  M",
            isSelected: session.recordingChoices.microphone
        ) { session.recordingChoices.microphone.toggle() }
        ScreenshotToolbarButton(
            symbol: session.recordingChoices.camera ? "person.crop.circle.fill" : "person.crop.circle.badge.xmark",
            title: session.recordingChoices.camera ? "Camera on  C" : "Camera off  C",
            isSelected: session.recordingChoices.camera
        ) { session.recordingChoices.camera.toggle() }
        ScreenshotToolbarDivider()
        ScreenshotToolbarButton(symbol: "xmark", title: "Cancel  Esc", tint: Theme.Colors.destructive) {
            perform(.cancel)
        }
        ScreenshotToolbarButton(
            symbol: "record.circle",
            title: session.recordingWindow == nil ? "Record the area  ↩" : "Record the window  ↩",
            tint: Theme.Colors.destructive
        ) { perform(.record) }
    }

    @ViewBuilder
    private var captureButtons: some View {
        ForEach(ScreenshotTool.allCases, id: \.self) { tool in
            if tool.startsGroup { ScreenshotToolbarDivider() }
            ScreenshotToolbarButton(
                symbol: tool.symbol, title: "\(tool.title)  \(tool.key.uppercased())",
                isSelected: session.tool == tool
            ) { edit(.choose(tool)) }
        }
        if session.purpose == .capture {
            ScreenshotToolbarButton(symbol: "ScreenshotPin", title: "Pin to screen") { perform(.pin) }
            ScreenshotToolbarButton(
                symbol: "ScreenshotScroll",
                title: session.isMarked ? "Scrolling capture needs an unmarked area" : "Scrolling capture",
                isEnabled: !session.isMarked
            ) { perform(.scroll) }
        }
        ScreenshotToolbarButton(symbol: "text.viewfinder", title: "Copy text  ⇧⌘T") { perform(.copyText) }
        ScreenshotToolbarDivider()
        ScreenshotToolbarButton(symbol: "arrow.uturn.backward", title: "Undo  ⌘Z", isEnabled: session.canUndo) {
            edit(.undo)
        }
        ScreenshotToolbarButton(symbol: "arrow.down.to.line", title: "Save  ⌘S") { perform(.save) }
        ScreenshotToolbarButton(symbol: "xmark", title: "Discard", tint: Theme.Colors.destructive) {
            perform(.cancel)
        }
        ScreenshotToolbarButton(symbol: "checkmark", title: "Copy  ↩ or Esc", tint: Theme.Colors.success) {
            perform(.copy)
        }
    }
}

struct ScreenshotToolbarButton: View {
    let symbol: String
    let title: String
    var tint = Theme.Colors.textPrimary
    var isSelected = false
    var isEnabled = true
    let action: () -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        BarButton(chrome: .rounded, isSelected: isSelected, isCompact: true, action: action) {
            SymbolImage(name: symbol, size: metrics.scaled(Theme.Size.noteGlyph))
                .foregroundStyle(isEnabled ? tint : Theme.Colors.textTertiary)
                .frame(width: metrics.scaled(Theme.Size.noteGlyph), height: metrics.scaled(Theme.Size.noteGlyph))
        }
        .disabled(!isEnabled)
        .focusable(false)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .tooltip(title)
    }
}

struct ScreenshotToolbarDivider: View {
    @Environment(\.metrics) private var metrics

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.border)
            .frame(width: Theme.Size.hairline, height: metrics.size.barButtonHeight * 0.6)
            .padding(.horizontal, metrics.spacing.xxs)
            .accessibilityHidden(true)
    }
}
