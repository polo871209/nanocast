import AppKit
import SwiftUI

struct WindowLayoutEditRequest: Identifiable {
    let id = UUID()
    var layout: WindowLayout?
    var isCapture = false
}

struct WindowLayoutEditorPanel: View {
    let request: WindowLayoutEditRequest

    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var draft: WindowLayoutDraft
    @State private var screens: [WindowLayoutScreen]
    @State private var errorMessage: String?

    init(request: WindowLayoutEditRequest) {
        self.request = request
        let connected = Self.connectedScreens()
        _screens = State(initialValue: connected)
        _draft = State(
            initialValue: WindowLayoutDraft(
                layout: request.layout, displays: connected.map(\.display)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                previewColumn
                Divider()
                WindowLayoutInspector(draft: draft, displays: screens.map(\.display))
                    .frame(width: Theme.Size.layoutInspectorColumn)
            }
            .frame(height: Theme.Size.layoutEditorSheet.height)
            Divider()
            footer
        }
        .frame(width: Theme.Size.layoutEditorSheet.width)
        .settingsEditorPanelSurface()
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification)
            {
                screens = Self.connectedScreens()
            }
        }
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(title)
                .font(Theme.Typography.panelTitle)
            WindowLayoutPreview(draft: draft, screens: screens, gap: previewGap)
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static func connectedScreens() -> [WindowLayoutScreen] {
        AXScreens.layoutScreens(geometry: AXGeometry(screens: NSScreen.screens))
    }

    private var title: String {
        if request.isCapture { return String(localized: "Capture Window Layout") }
        return request.layout == nil
            ? String(localized: "New Window Layout") : String(localized: "Edit Window Layout")
    }

    private var previewGap: CGFloat {
        draft.usesPreferredGap ? CGFloat(settings.windowGap) : 0
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.xl) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Cancel") { dismiss() }
                .buttonStyle(.modalAction(.cancel, fillsWidth: false))
                .keyboardShortcut(.cancelAction)
            Button(action: save) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Save")
                    HStack(spacing: Theme.Spacing.xxs) {
                        KeyCapChip(text: "⌘", scale: .compact)
                        KeyCapChip(text: "↵", scale: .compact)
                    }
                }
            }
            .buttonStyle(.modalAction(.primary, fillsWidth: false))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!draft.canSave)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private func save() {
        guard draft.canSave else { return }
        let value = draft.layout()
        do {
            if draft.existingID == nil || core.windowLayouts.layout(id: value.id) == nil {
                try core.windowLayoutCoordinator.addWindowLayout(value)
            } else {
                try core.windowLayoutCoordinator.updateWindowLayout(value)
            }
            dismiss()
        } catch {
            errorMessage = error.errorDescription
        }
    }
}
