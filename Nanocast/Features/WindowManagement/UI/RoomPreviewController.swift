// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
import SwiftUI

struct RoomPreviewCard: Identifiable, Equatable {
    let id: String
    var frame: CGRect
    var appName: String
    var title: String
    var appURL: URL?
}

@MainActor
@Observable
final class RoomPreviewModel {
    var cards: [RoomPreviewCard] = []
    var avoiding: CGRect?
}

@MainActor
final class RoomPreviewController {
    private let model = RoomPreviewModel()
    private var panels: [RoomPreviewPanel] = []

    var isShowing: Bool { !panels.isEmpty }

    func show(_ cards: [RoomPreviewCard], avoiding: CGRect?) {
        let geometry = AXGeometry(screens: NSScreen.screens)
        model.avoiding = avoiding.map(geometry.flip)
        guard isShowing else {
            model.cards = cards
            open(geometry: geometry)
            return
        }
        let glide = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : Theme.RoomMotion.glide
        withAnimation(glide) { model.cards = cards }
    }

    func hide(settling: Bool = false) {
        guard isShowing else { return }
        let closing = panels
        panels = []
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            closing.forEach { $0.orderOut(nil) }
            model.cards = []
            return
        }
        let duration = settling ? Theme.Duration.roomSettle : Theme.Duration.exit
        for panel in closing {
            panel.fadeOut(duration: duration) { [weak self] in
                guard let self, !self.isShowing else { return }
                self.model.cards = []
            }
        }
    }

    private func open(geometry: AXGeometry) {
        panels = NSScreen.screens.map { screen in
            let frame = geometry.flip(screen.frame)
            let host = NSHostingView(
                rootView: RoomPreviewView(model: model, origin: frame.origin, size: frame.size))
            host.sizingOptions = []
            let panel = RoomPreviewPanel()
            panel.contentView = host
            panel.setFrame(screen.frame, display: false)
            return panel
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for panel in panels {
            if reduceMotion {
                panel.orderFrontRegardless()
            } else {
                panel.fadeIn(duration: Theme.Duration.roomCardEnter) { panel.orderFrontRegardless() }
            }
        }
    }
}

private final class RoomPreviewPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .paletteDropGuide
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
