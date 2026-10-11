import AppKit
import SwiftUI

struct ShortcutRecorder: View {
    let action: HotKeyAction
    var isQuiet = false

    @Environment(HotKeyManager.self) private var hotKeys
    private var modifierTapMonitor: ModifierTapMonitor { hotKeys.modifierTapMonitor }
    @State private var hovered = false

    private var isRecording: Bool { hotKeys.recordingAction == action }

    private var unsetInk: Color {
        isRecording || !isQuiet || hovered
            ? Theme.Colors.textSecondary : Theme.Colors.textTertiary
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        let showsFill = !isQuiet || isRecording || hovered || hotKeys.binding(for: action) != nil
        content
            .padding(.horizontal, Theme.Spacing.sm + 1)
            .frame(width: Theme.Size.shortcutRecorder, height: 24)
            .background(shape.fill(Theme.Colors.cardFill).opacity(showsFill ? 1 : 0))
            .background {
                if isRecording { ShortcutRecorderHitRegion(capture: hotKeys.capture) }
            }
            .overlay(shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { hotKeys.recordingAction = isRecording ? nil : action }
            .onHover { hovered = $0 }
            .anchorPreference(key: ShortcutRecorderAnchorKey.self, value: .bounds) {
                isRecording ? $0 : nil
            }
            .onDisappear { if isRecording { hotKeys.recordingAction = nil } }
            .onChange(of: action) { old, _ in
                if hotKeys.recordingAction == old { hotKeys.recordingAction = nil }
            }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }

    @ViewBuilder
    private var content: some View {
        if let binding = hotKeys.binding(for: action) {
            boundLabel(binding)
        } else {
            Text(isRecording ? "Listening…" : "Record Hotkey")
                .font(Theme.Typography.keyCap)
                .foregroundStyle(unsetInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func boundLabel(_ binding: HotKeyBinding) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if binding.usesModifierTapMonitor, modifierTapMonitor.needsAccessibility {
                Button {
                    Permissions.openAccessibilitySettings()
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Accessibility settings")
                .help("Modifier-only hotkeys need Accessibility access. Click to grant it.")
            }
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(binding.recorderKeycaps.enumerated()), id: \.offset) { _, cap in
                    KeyCapChip.Label(text: cap, prefix: binding.recorderPrefix)
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .frame(
                            minWidth: Theme.Size.recorderKeyCap, minHeight: Theme.Size.recorderKeyCap
                        )
                        .background(
                            RoundedRectangle(
                                cornerRadius: Theme.Radius.recorderKeyCap, style: .continuous
                            )
                            .fill(Color.primary.opacity(0.08))
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(KeyCapChip.inlineText(binding.keycaps, separator: " "))
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Button {
                hotKeys.setBinding(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
        }
    }
}

private struct ShortcutRecorderHitRegion: NSViewRepresentable {
    let capture: ShortcutCaptureSession

    func makeNSView(context: Context) -> PassiveView {
        let view = PassiveView()
        view.capture = capture
        capture.setActiveRecorderView(view)
        return view
    }

    func updateNSView(_ view: PassiveView, context: Context) {
        if view.capture !== capture { view.capture?.clearActiveRecorderView(view) }
        view.capture = capture
        capture.setActiveRecorderView(view)
    }

    static func dismantleNSView(_ view: PassiveView, coordinator: ()) {
        view.capture?.clearActiveRecorderView(view)
    }

    final class PassiveView: NSView {
        weak var capture: ShortcutCaptureSession?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
