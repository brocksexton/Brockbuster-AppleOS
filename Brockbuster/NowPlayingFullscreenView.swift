import SwiftUI
import AVKit

/// Fullscreen player UI driven by NowPlayingManager's AVPlayer.
/// Uses AVPlayerViewController so we get subtitles/audio selection and PiP.
struct NowPlayingFullscreenView: View {
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    @Environment(\.dismiss) private var dismiss

    @State private var overlayVisible: Bool = true
    @State private var overlayHideTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack(alignment: .top) {
            if let player = nowPlaying.currentPlayer() {
                AVPlayerViewControllerRepresentable(player: player)
                    .ignoresSafeArea()
                    // AVPlayerViewController aggressively consumes touch events.
                    // Use a simultaneous gesture so taps still toggle our overlay.
                    .simultaneousGesture(
                        TapGesture().onEnded { handleToggleOverlay() }
                    )
            } else {
                Color.black
                    .ignoresSafeArea()
                    .onTapGesture { handleToggleOverlay() }
            }

            if overlayVisible {
                overlay
                    .transition(.opacity)
            }
        }
        .onAppear {
            scheduleOverlayAutoHide()
        }
        .onDisappear {
            // If the user dismisses the fullscreen player, we minimize into the Now Playing bar.
            nowPlaying.minimizePlayer()
            overlayHideTask?.cancel()
        }
    }

    private func handleToggleOverlay() {
        // IMPORTANT: Do not *toggle* the overlay on tap.
        // AVPlayerViewController already uses taps to show/hide its own controls.
        // If we also toggle, the two systems "fight" each other and it feels glitchy.
        //
        // Behavior:
        // - If overlay is hidden, a tap reveals it.
        // - If overlay is visible, a tap just resets the auto-hide timer.
        if !overlayVisible {
            withAnimation(.easeInOut(duration: 0.20)) {
                overlayVisible = true
            }
        }
        scheduleOverlayAutoHide()
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

            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.item?.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let sub = nowPlaying.item?.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(.leading, 2)

            Spacer(minLength: 0)

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

    private func scheduleOverlayAutoHide() {
        overlayHideTask?.cancel()
        overlayHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.20)) {
                overlayVisible = false
            }
        }
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
