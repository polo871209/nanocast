import SwiftUI

struct FileToolsList: View {
    @Environment(\.metrics) private var metrics
    let tools: [FileTool]
    let selectedID: FileTool.ID?
    let scroll: ScrollIntent
    let onSelect: (FileTool) -> Void
    let onActivate: (FileTool) -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == tools.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                        if index == 0 || tools[index - 1].section != tool.section {
                            SectionHeader(title: tool.section.title, isFirst: index == 0)
                        }
                        FileToolRow(tool: tool, selected: tool.id == selectedID)
                            .selectionFrame(tool.id == selectedID)
                            .contentShape(Rectangle())
                            .onRowClick(select: { onSelect(tool) }, activate: { onActivate(tool) })
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct FileToolRow: View {
    @Environment(\.metrics) private var metrics
    let tool: FileTool
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Image(systemName: tool.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(tool.title)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
