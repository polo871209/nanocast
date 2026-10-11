import SwiftUI
import UniformTypeIdentifiers

struct FileSearchPreview: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult?

    var body: some View {
        if let result {
            VStack(alignment: .leading, spacing: 0) {
                FileSearchPreviewStage(result: result)
                    .aspectRatio(Theme.Size.previewAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                ScrollView {
                    FileSearchInfoSection(result: result)
                }
            }
            .padding(.horizontal, metrics.spacing.xl)
        } else {
            Color.clear
        }
    }
}

private struct FileSearchPreviewStage: View {

    @Environment(\.metrics) private var metrics
    @Environment(PaletteState.self) private var palette
    let result: FileSearchResult

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
    }

    var body: some View {
        stage
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, metrics.spacing.xl)
    }

    @ViewBuilder private var stage: some View {
        if result.isDirectory {
            Image(systemName: "folder")
                .font(.system(.largeTitle))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
        } else if palette.isVisible {
            FileSearchSurface(url: result.url)
                .clipShape(card)
                .overlay(card.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
        } else {
            Color.clear
        }
    }
}

private struct FileSearchInfoSection: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult
    @State private var details = Details()

    private struct Details: Equatable, Sendable {
        var typeName: String?
        var bytes: Int?
        var created: Date?
        var modified: Date?
    }

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    @MainActor private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Information")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(row.value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
        .padding(.vertical, metrics.spacing.md)
        .task(id: result.id) { await loadDetails() }
    }

    private var rows: [InfoRow] {
        var rows = [
            InfoRow(label: String(localized: "Name"), value: result.name),
            InfoRow(label: String(localized: "Where"), value: result.parentPath),
            InfoRow(
                label: String(localized: "Type"),
                value: details.typeName
                    ?? (result.isDirectory ? String(localized: "Folder") : String(localized: "File")))
        ]
        if let bytes = details.bytes {
            rows.append(
                InfoRow(
                    label: String(localized: "Size"),
                    value: Int64(bytes).formatted(.byteCount(style: .file))))
        }
        if let created = details.created {
            rows.append(
                InfoRow(
                    label: String(localized: "Created"),
                    value: Self.stampFormatter.string(from: created)))
        }
        if let modified = details.modified {
            rows.append(
                InfoRow(
                    label: String(localized: "Modified"),
                    value: Self.stampFormatter.string(from: modified)))
        }
        return rows
    }

    private nonisolated static func sentenceCased(_ name: String) -> String {
        name.prefix(1).localizedUppercase + name.dropFirst()
    }

    private func loadDetails() async {
        details = Details()
        let url = result.url
        let isDirectory = result.isDirectory
        details = await Task.detached(priority: .userInitiated) {
            let values = try? url.resourceValues(forKeys: [
                .contentTypeKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey
            ])
            return Details(
                typeName: values?.contentType?.localizedDescription.map(Self.sentenceCased),
                bytes: isDirectory ? nil : values?.fileSize,
                created: values?.creationDate,
                modified: values?.contentModificationDate)
        }.value
    }
}
