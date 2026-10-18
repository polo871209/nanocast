import SwiftUI

struct FileToolsPane: View {
    @Environment(\.metrics) private var metrics
    let subject: FileToolsSubject
    let file: FileSearchResult?
    let tool: FileTool?
    let option: FileToolOption?
    let job: FileToolsSession.Job?
    let outcome: FileToolsSession.Outcome?
    let onChoose: (FileToolOption) -> Void
    let onRun: () -> Void
    let onCancel: () -> Void

    private var outputDescription: String? {
        guard let tool, let first = subject.first else { return nil }
        switch tool.output(for: first.url) {
        case .text:
            return "Copied to the clipboard"
        case .none:
            return nil
        case .file, .folder:
            if subject.isBatch, !tool.combinesSources {
                return "\(subject.items.count) new files beside the originals"
            }
            return FileToolOutputName.destination(
                for: tool, option: option, sources: subject.urls,
                isTaken: { FileManager.default.fileExists(atPath: $0.path) }
            )?.lastPathComponent
        }
    }

    private var subjectName: String {
        subject.isBatch ? "\(subject.items.count) files" : subject.first?.name ?? ""
    }

    private var folderPath: String {
        guard let folder = subject.first?.url.deletingLastPathComponent().path else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let file {
                    FileSearchPreviewStage(result: file)
                } else {
                    FileToolsIconStack(urls: subject.urls)
                }
            }
            .aspectRatio(Theme.Size.previewAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.spacing.md) {
                    if let outcome, outcome.outputs == subject.urls {
                        FileToolsOutcomeLine(outcome: outcome)
                    }
                    details
                    if let tool, !tool.options.isEmpty {
                        options(for: tool)
                    }
                    if let field = tool?.fields.first {
                        Text(field.hint)
                            .font(metrics.typography.keyCap)
                            .foregroundStyle(.secondary)
                    }
                    runRow
                }
                .padding(.vertical, metrics.spacing.md)
            }
        }
        .padding(.horizontal, metrics.spacing.xl)
    }

    private var details: some View {
        VStack(spacing: 0) {
            detailRow(subject.isBatch ? "Files" : "File", value: subjectName)
            if let outputDescription {
                Divider()
                detailRow("Output", value: outputDescription)
            }
            Divider()
            detailRow("Where", value: folderPath)
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: metrics.spacing.lg)
            Text(value).lineLimit(1).truncationMode(.middle)
        }
        .font(metrics.typography.keyCap)
        .padding(.vertical, metrics.spacing.xs)
    }

    private func options(for tool: FileTool) -> some View {
        HStack(spacing: metrics.spacing.xs) {
            ForEach(tool.options, id: \.self) { candidate in
                BarButton(chrome: .rounded, isSelected: candidate == option, isCompact: true) {
                    onChoose(candidate)
                } label: {
                    Text(candidate.title).font(metrics.typography.keyCap)
                }
            }
            Spacer(minLength: metrics.spacing.sm)
            KeyCapChip(text: "⇥", style: .outline, scale: .compact)
                .help("Tab picks the next option")
        }
    }

    @ViewBuilder
    private var runRow: some View {
        if let job {
            HStack(spacing: metrics.spacing.sm) {
                if let progress = job.progress {
                    ProgressView(value: progress)
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Working…").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                BarButton(action: onCancel) {
                    Text("Cancel Job")
                }
            }
            .font(metrics.typography.keyCap)
        } else if let tool {
            HStack(spacing: metrics.spacing.sm) {
                Spacer(minLength: 0)
                BarButton(action: onRun) {
                    HStack(spacing: metrics.spacing.sm) {
                        Text(tool.verb)
                        KeyCapChip(text: "↵", scale: .compact)
                    }
                }
            }
            .font(metrics.typography.keyCap)
        }
    }
}

private struct FileToolsIconStack: View {
    @Environment(\.metrics) private var metrics
    let urls: [URL]

    private static let shown = 3

    var body: some View {
        let front = Array(urls.prefix(Self.shown))
        ZStack {
            ForEach(Array(front.enumerated().reversed()), id: \.offset) { index, url in
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: Theme.Size.fileStackIcon, height: Theme.Size.fileStackIcon)
                    .rotationEffect(.degrees(Double(index - 1) * Theme.Size.fileStackTilt))
                    .offset(x: CGFloat(index) * metrics.spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileToolsOutcomeLine: View {
    @Environment(\.metrics) private var metrics
    let outcome: FileToolsSession.Outcome

    private var summary: String {
        switch outcome.kind {
        case .moved(let folder): return "Moved to \(folder)"
        case .copied(let folder): return "Copied to \(folder)"
        case .saved: break
        }
        guard let output = outcome.outputBytes else { return "Saved" }
        let size = Int64(output).formatted(.byteCount(style: .file))
        guard let input = outcome.inputBytes, input > 0 else { return "Saved, \(size)" }
        let change = Int((Double(output - input) / Double(input) * 100).rounded())
        if change < 0 { return "Saved, \(size), \(-change)% smaller" }
        if change > 0 { return "Saved, \(size), \(change)% larger" }
        return "Saved, \(size), same size"
    }

    private var note: String? {
        guard outcome.kind == .saved else { return nil }
        return outcome.outputs.count == 1 ? "Path copied" : "Paths copied"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Label(summary, systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.success)
            if let note {
                Text(note).foregroundStyle(.secondary)
            }
        }
        .font(metrics.typography.keyCap)
    }
}
