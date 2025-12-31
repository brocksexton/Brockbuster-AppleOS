import SwiftUI
import AVKit

/// Full-screen player backed by `AVPlayerViewController`.
///
/// We intentionally use AVKit so we get native Apple playback UX:
/// - playback controls
/// - subtitles/CC selection (when tracks exist)
/// - audio track selection (when tracks exist)
/// - Picture in Picture
///
/// Brockbuster additions:
/// - Lightweight overlay (title/subtitle/poster + close)
/// - Automatic fallback to a Jellyfin transcoded HLS stream if the initial URL
///   fails to play on the device (unsupported container/codec).
struct PlayerView: View {
    /// Jellyfin item id currently being played (movie/episode).
    let itemId: String

    /// Initial stream URL (usually direct play).
    let url: URL

    /// Overlay title (movie or series name).
    let title: String

    /// Overlay subtitle (e.g., S1E2 • Episode Name).
    let subtitle: String?

    /// Optional poster or logo to show in the overlay.
    let posterURL: URL?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var currentURL: URL
    @State private var showOverlay: Bool = true
    @State private var overlayHideTask: Task<Void, Never>?

    @State private var didFallbackToTranscode: Bool = false
    @State private var isSwitchingStream: Bool = false
    @State private var errorMessage: String?

    init(itemId: String, url: URL, title: String, subtitle: String?, posterURL: URL?) {
        self.itemId = itemId
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
        _currentURL = State(initialValue: url)
    }

    var body: some View {
        ZStack(alignment: .top) {
            PlayerViewControllerRepresentable(
                url: currentURL,
                onUserInteraction: {
                    // Re-show the metadata overlay whenever the user interacts with the player UI.
                    showOverlayNow()
                },
                onPlaybackFailed: { err in
                    Task { await handlePlaybackFailure(err) }
                }
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            // NOTE: AVPlayerViewController often consumes taps; the UIKit gesture inside the
            // representable is the primary mechanism for restoring the overlay.
            .onTapGesture { showOverlayNow() }

            if showOverlay {
                overlay
                    .transition(.opacity)
                    .onAppear { scheduleOverlayAutoHide() }
            }

            if isSwitchingStream {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Optimizing playback…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 30)
                }
                .transition(.opacity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onDisappear { overlayHideTask?.cancel() }
        .alert("Playback Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Close") { dismiss() }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var overlay: some View {
        HStack(spacing: 12) {
            if let posterURL {
                AsyncImage(url: posterURL) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.25))
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.25))
                            .overlay(Image(systemName: "film").foregroundColor(.white))
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 40, height: 40)
                .clipped()
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(subtitle ?? "Brockbuster")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.75), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private func toggleOverlay() {
        // Kept for potential future use. The current UX preference is:
        // - user interaction should always show the overlay
        // - overlay auto-hides after a delay
        showOverlayNow()
    }

    private func showOverlayNow() {
        overlayHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            showOverlay = true
        }
        scheduleOverlayAutoHide()
    }

    private func scheduleOverlayAutoHide() {
        overlayHideTask?.cancel()
        overlayHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                showOverlay = false
            }
        }
    }

    private func handlePlaybackFailure(_ error: Error?) async {
        // If we've already switched to a transcoded stream and still fail, show an error.
        if didFallbackToTranscode {
            await MainActor.run {
                errorMessage = "This item could not be played. \(error?.localizedDescription ?? "")"
            }
            return
        }

        await MainActor.run { isSwitchingStream = true }
        do {
            let fallbackURL = try await session.transcodedHLSURL(for: itemId)
            await MainActor.run {
                didFallbackToTranscode = true
                currentURL = fallbackURL
                isSwitchingStream = false
                withAnimation(.easeInOut(duration: 0.18)) { showOverlay = true }
                scheduleOverlayAutoHide()
            }
        } catch {
            await MainActor.run {
                isSwitchingStream = false
                errorMessage = "Playback failed and a compatible stream could not be requested. \(error.localizedDescription)"
            }
        }
    }
}

private struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let url: URL
    let onUserInteraction: () -> Void
    let onPlaybackFailed: (Error?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onUserInteraction: onUserInteraction, onPlaybackFailed: onPlaybackFailed)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true

        // Prevent the "white box" look while the player is preparing.
        controller.view.backgroundColor = .black

        // Capture taps even when AVPlayerViewController consumes touches.
        context.coordinator.attachInteractionRecognizer(to: controller)

        context.coordinator.attach(to: player)

        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if let current = (uiViewController.player?.currentItem?.asset as? AVURLAsset)?.url,
           current != url {
            let player = AVPlayer(url: url)
            uiViewController.player = player
            context.coordinator.attach(to: player)
            player.play()
        }
    }

    final class Coordinator: NSObject {
        private let onUserInteraction: () -> Void
        private let onPlaybackFailed: (Error?) -> Void
        private var failedObserver: NSObjectProtocol?
        private weak var controller: AVPlayerViewController?

        init(onUserInteraction: @escaping () -> Void, onPlaybackFailed: @escaping (Error?) -> Void) {
            self.onUserInteraction = onUserInteraction
            self.onPlaybackFailed = onPlaybackFailed
        }

        deinit {
            if let obs = failedObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        func attach(to player: AVPlayer) {
            if let obs = failedObserver {
                NotificationCenter.default.removeObserver(obs)
                failedObserver = nil
            }

            if let item = player.currentItem {
                failedObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemFailedToPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] note in
                    guard let self else { return }
                    let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    self.onPlaybackFailed(err)
                }
            }
        }

        func attachInteractionRecognizer(to controller: AVPlayerViewController) {
            self.controller = controller

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false

            // Prefer contentOverlayView if available so we don't interfere with the player's own gestures.
            if let overlay = controller.contentOverlayView {
                overlay.addGestureRecognizer(tap)
            } else {
                controller.view.addGestureRecognizer(tap)
            }
        }

        @objc private func handleTap() {
            onUserInteraction()
        }
    }
}
