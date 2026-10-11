import AVKit
import SwiftUI

struct FileSearchMediaPlayer: View {

    @Environment(PaletteState.self) private var palette
    let url: URL
    @State private var player: AVPlayer?

    private struct PlaybackKey: Equatable {
        let url: URL
        let isVisible: Bool
    }

    var body: some View {
        PlayerSurface(player: player)
            .task(id: PlaybackKey(url: url, isVisible: palette.isVisible)) {
                stop()
                guard palette.isVisible else { return }
                player = AVPlayer(url: url)
            }
            .onDisappear(perform: stop)
    }

    private func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

/// `AVPlayerView`, since SwiftUI's `VideoPlayer` traps instantiating its own generic metadata.
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = PreviewPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard view.player !== player else { return }
        view.player = player
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

private final class PreviewPlayerView: AVPlayerView, KeyboardFocusRefusing {}
