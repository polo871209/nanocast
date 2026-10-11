import SwiftUI

struct WindowSwitchView: View {
    let session: WindowSwitchSession
    let grid: WindowSwitchGrid
    let onChoose: (Int) -> Void

    private var rows: [Range<Int>] {
        stride(from: 0, to: session.entries.count, by: grid.columns).map {
            $0..<min($0 + grid.columns, session.entries.count)
        }
    }

    var body: some View {
        let spacing = Theme.Size.switcherGap * grid.scale
        VStack(spacing: spacing) {
            ForEach(rows, id: \.lowerBound) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { index in
                        let entry = session.entries[index]
                        WindowSwitchTile(
                            entry: entry, preview: entry.windowID.flatMap { session.previews[$0] },
                            selected: index == session.selection, scale: grid.scale
                        )
                        .onTapGesture { onChoose(index) }
                    }
                }
            }
        }
        .padding(Theme.Size.switcherPadding * grid.scale)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.switcherPanel, style: .continuous))
    }
}

private struct WindowSwitchTile: View {
    let entry: WindowSwitchEntry
    let preview: CGImage?
    let selected: Bool
    let scale: CGFloat

    private var thumbnail: CGSize {
        CGSize(
            width: Theme.Size.switcherThumbnail.width * scale,
            height: Theme.Size.switcherThumbnail.height * scale)
    }

    var body: some View {
        content
            .frame(width: thumbnail.width, height: thumbnail.height)
            .padding(Theme.Size.switcherSelectionInset * scale)
            .background { if selected { plate } }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.label)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var content: some View {
        if let preview {
            Image(decorative: preview, scale: 1)
                .resizable()
                .scaledToFit()
                .clipShape(
                    RoundedRectangle(cornerRadius: Theme.Radius.switcherThumbnail, style: .continuous)
                )
                .overlay(alignment: .topLeading) {
                    icon
                        .frame(
                            width: Theme.Size.switcherBadgeIcon * scale,
                            height: Theme.Size.switcherBadgeIcon * scale
                        )
                        .padding(Theme.Size.switcherBadgeInset * scale)
                }
        } else {
            icon.frame(
                width: Theme.Size.switcherPlaceholderIcon * scale,
                height: Theme.Size.switcherPlaceholderIcon * scale)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let iconURL = entry.iconURL {
            EntryIconView(source: .file(stamp: entry.iconStamp), fileURL: iconURL)
        } else {
            EntryIconView(source: .symbol("macwindow"))
        }
    }

    private var plate: some View {
        let shape = RoundedRectangle(
            cornerRadius: Theme.Radius.switcherSelection * scale, style: .continuous)
        return shape.fill(Theme.Colors.switcherSelection)
            .overlay(
                shape.strokeBorder(
                    Theme.Colors.switcherSelectionRim, lineWidth: Theme.Size.switcherSelectionStroke))
    }
}
