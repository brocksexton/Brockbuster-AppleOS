import SwiftUI
import AVKit

/// Fullscreen player UI driven by NowPlayingManager's AVPlayer.
/// Uses AVPlayerViewController so we get subtitles/audio selection and PiP.
struct NowPlayingFullscreenView: View {
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            if let player = nowPlaying.currentPlayer() {
                AVPlayerViewControllerRepresentable(player: player)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            overlay
        }
        .onDisappear {
            // If the user dismisses the fullscreen player, we minimize into the Now Playing bar.
            nowPlaying.minimizePlayer()
        }
    }

    private var overlay: some View {
        HStack(spacing: 10) {
            Button {
                // Minimize
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                nowPlaying.stop(playedToCompletion: false, failed: false)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        #if os(iOS) || os(visionOS)
        vc.allowsPictureInPicturePlayback = true
        #endif
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
