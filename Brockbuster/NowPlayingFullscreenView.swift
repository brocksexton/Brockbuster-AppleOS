import SwiftUI
import AVKit

/// Fullscreen player UI driven by NowPlayingManager's AVPlayer.
/// Uses AVPlayerViewController so we get subtitles/audio selection and PiP.
struct NowPlayingFullscreenView: View {
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    @Environment(\.dismiss) private var dismiss

    @State private var overlayVisible: Bool = true
    @State private var overlayHideTask: Task<Void, Never>? = nil

    @State private var upNextTick: Int = 0

    private let upNextTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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

            // Loading state: show while we are obtaining the stream URL / play session.
            if nowPlaying.currentPlayer() == nil || nowPlaying.isPreparingPlayback {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                    .padding(.bottom, 34)
                }
                .transition(.opacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            if overlayVisible {
                overlay
                    .transition(.opacity)
            }

            // Skip Intro (if Jellyfin provides an intro segment)
            if shouldShowSkipIntro {
                skipIntroButton
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Up Next prompt
            if let state = nowPlaying.upNext {
                upNextOverlay(state: state)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            scheduleOverlayAutoHide()
        }
        .onReceive(upNextTimer) { _ in
            upNextTick &+= 1
            if let state = nowPlaying.upNext {
                let remaining = max(0, state.countdownSeconds - Int(Date().timeIntervalSince(state.createdAt)))
                if remaining == 0 {
                    nowPlaying.playNextUpNow()
                }
            }
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

    // MARK: - Skip Intro

    private var shouldShowSkipIntro: Bool {
        guard let window = nowPlaying.introWindow else { return false }
        let pos = nowPlaying.currentPositionTicks
        return pos >= window.startTicks && pos <= window.endTicks
    }

    private var skipIntroButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    guard let window = nowPlaying.introWindow,
                          let player = nowPlaying.currentPlayer() else { return }
                    let seconds = SessionStore.ticksToSeconds(window.endTicks)
                    player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
                } label: {
                    Text("Skip Intro")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 18)
                .padding(.bottom, 86) // keep above native transport controls
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Up Next

    private func upNextOverlay(state: NowPlayingManager.UpNextState) -> some View {
        let remaining = max(0, state.countdownSeconds - Int(Date().timeIntervalSince(state.createdAt)))

        return VStack {
            Spacer()

            HStack(spacing: 12) {
                // Thumbnail
                BBCachedAsyncImage(url: state.posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Rectangle().fill(.white.opacity(0.08))
                    }
                }
                .frame(width: 88, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Up Next")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))

                    Text(state.subtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(remaining > 0 ? "Playing in \(remaining)s" : "Playing now")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }

                Spacer(minLength: 0)

                Button {
                    nowPlaying.playNextUpNow()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    nowPlaying.cancelAutoplayNext()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.45), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 26)
        }
        .ignoresSafeArea()
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
