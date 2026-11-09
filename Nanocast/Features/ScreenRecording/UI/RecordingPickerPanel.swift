import AppKit
import SwiftUI

@MainActor
final class RecordingPickerPanel {
    private let panel: KeyPanel
    private let model: RecordingPickerModel

    init(on screen: NSScreen, metrics: InterfaceMetrics, picked: @escaping (RecordingTarget?) -> Void) {
        let model = RecordingPickerModel()
        self.model = model
        weak var picker: RecordingPickerPanel?
        let finish: (RecordingTarget?) -> Void = { target in
            picker?.close()
            picked(target)
        }
        let content = NSHostingView(rootView: RecordingPickerView(model: model, metrics: metrics, finish: finish))
        let size = content.fittingSize
        panel = KeyPanel(
            contentRect: CGRect(
                x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2,
                width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenshot
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content
        panel.cancel = { finish(nil) }
        picker = self
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        model.loadThumbnails()
    }

    func close() {
        model.cancel()
        panel.orderOut(nil)
        panel.contentView = nil
    }
}

private final class KeyPanel: NSPanel {
    var cancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        cancel?()
    }
}

private struct PickerItem: Identifiable {
    let id: RecordingSubject
    let title: String
    let icon: NSImage?

    var target: RecordingTarget {
        switch id {
        case .display(let display): .display(display)
        case .window(let window): .window(window)
        }
    }
}

@MainActor
@Observable
private final class RecordingPickerModel {
    let items: [PickerItem]
    var thumbnails: [RecordingSubject: CGImage] = [:]
    @ObservationIgnored private var loading: Task<Void, Never>?

    init() {
        let screens = NSScreen.screens
        let displays = screens.compactMap { screen in
            screen.displayID.map { id in
                PickerItem(
                    id: .display(id), title: screens.count == 1 ? "Entire Desktop" : screen.localizedName, icon: nil)
            }
        }
        let windows = RecordingWindows.onScreen().map { window in
            PickerItem(
                id: .window(window.id), title: window.title,
                icon: NSRunningApplication(processIdentifier: window.processID)?.icon)
        }
        items = displays + windows
    }

    func loadThumbnails() {
        let subjects = items.map(\.id)
        loading = Task { [weak self] in
            await RecordingWindows.thumbnails(of: subjects, pixelHeight: 300) { subject, image in
                self?.thumbnails[subject] = image
            }
        }
    }

    func cancel() {
        loading?.cancel()
    }
}

private struct RecordingPickerView: View {
    let model: RecordingPickerModel
    let metrics: InterfaceMetrics
    let finish: (RecordingTarget?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            HStack {
                Text("Choose what to record")
                    .font(metrics.typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                ScreenshotToolbarButton(symbol: "xmark", title: "Cancel  Esc") { finish(nil) }
            }
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(card.width), spacing: metrics.spacing.md),
                        count: Theme.Markup.recordingPickerColumns),
                    spacing: metrics.spacing.md
                ) {
                    ForEach(model.items) { item in
                        PickerCard(item: item, thumbnail: model.thumbnails[item.id], card: card) {
                            finish(item.target)
                        }
                    }
                }
            }
            .frame(width: gridWidth, height: gridHeight)
        }
        .padding(metrics.spacing.xl)
        .screenshotChrome(metrics)
    }

    private var card: CGSize {
        CGSize(
            width: metrics.scaled(Theme.Markup.recordingPickerCard.width),
            height: metrics.scaled(Theme.Markup.recordingPickerCard.height))
    }

    private var gridWidth: CGFloat {
        let columns = CGFloat(Theme.Markup.recordingPickerColumns)
        return card.width * columns + metrics.spacing.md * (columns - 1)
    }

    private var gridHeight: CGFloat {
        let rows = CGFloat(
            min((model.items.count + Theme.Markup.recordingPickerColumns - 1) / Theme.Markup.recordingPickerColumns, 3))
        return (card.height + metrics.spacing.md) * rows - metrics.spacing.md
    }
}

private struct PickerCard: View {
    let item: PickerItem
    let thumbnail: CGImage?
    let card: CGSize
    let pick: () -> Void
    @State private var isHovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                        .fill(Theme.Colors.selection)
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 2)
                            .resizable()
                            .scaledToFit()
                            .padding(metrics.spacing.xs)
                    }
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: metrics.spacing.xs) {
                    if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(
                                width: metrics.scaled(Theme.Markup.recordingPickerIcon),
                                height: metrics.scaled(Theme.Markup.recordingPickerIcon))
                    }
                    Text(item.title)
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(metrics.spacing.xs)
            .frame(width: card.width, height: card.height)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                    .fill(isHovered ? Theme.Colors.rowHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(item.title)
    }
}
