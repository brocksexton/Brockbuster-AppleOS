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

    /// Playback context (mediaSourceId/playSessionId) used for reporting playback to Jellyfin.
    let playbackContext: SessionStore.PlaybackContext?

    /// Resume position in Jellyfin ticks (10,000,000 ticks = 1 second).
    let startPositionTicks: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: SessionStore

    @State private var currentURL: URL
    @State private var avPlayer: AVPlayer?
    @State private var timeObserverToken: Any?
    @State private var lastProgressReportTicks: Int = 0
    /// Tracks the last known position so we can persist progress even if the
    /// player is dismissed before the periodic progress timer fires.
    @State private var lastKnownPositionTicks: Int = 0
    @State private var didPlayToEnd: Bool = false
    @State private var hasReportedStart: Bool = false
    @State private var showOverlay: Bool = true
    @State private var overlayHideTask: Task<Void, Never>?

    @State private var didFallbackToTranscode: Bool = false
    @State private var isSwitchingStream: Bool = false
    @State private var errorMessage: String?

    // Subtitles (Closed Captions)
    @State private var subtitlesAvailable: Bool = false
    @State private var subtitlesEnabled: Bool = false

    /// Set to true only when the user explicitly dismisses the player.
    /// We avoid tearing down playback when the app temporarily backgrounds
    /// to improve resume responsiveness.
    @State private var userInitiatedDismissal: Bool = false

    init(itemId: String, url: URL, title: String, subtitle: String?, posterURL: URL?, playbackContext: SessionStore.PlaybackContext? = nil, startPositionTicks: Int = 0) {
        self.itemId = itemId
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.playbackContext = playbackContext
        self.startPositionTicks = startPositionTicks
        _currentURL = State(initialValue: url)
    }

    var body: some View {
        ZStack(alignment: .top) {
            PlayerViewControllerRepresentable(
                url: currentURL,
                startPositionTicks: startPositionTicks,
                onPlayerReady: { player in
                    attachPlayer(player)
                },
                onPlaybackStarted: { currentTicks in
                    Task { await reportPlaybackStarted(initialTicks: currentTicks) }
                },
                onPlaybackEnded: {
                    didPlayToEnd = true
                    Task { await reportPlaybackStopped(playedToCompletion: true, failed: false) }
                },
                onUserInteraction: {
                    // Re-show the metadata overlay whenever the user interacts with the player UI.
                    showOverlayNow()
                },
                onPlaybackFailed: { err in
                    Task {
                        await reportPlaybackStopped(playedToCompletion: false, failed: true)
                        await handlePlaybackFailure(err)
                    }
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
        .onAppear {
            AudioSessionManager.shared.configureForPlaybackIfNeeded()
        }
        .onDisappear {
            overlayHideTask?.cancel()

            // Important: When the app backgrounds (Control Center, lock screen,
            // app switcher), SwiftUI can trigger onDisappear for some view
            // hierarchies. Tearing down the AVPlayer in that scenario forces a
            // full stream re-setup on return, which feels sluggish.
            //
            // Only teardown when the player was intentionally dismissed.
            guard userInitiatedDismissal, scenePhase == .active else {
                return
            }

            // Send a final progress update before stopping so Jellyfin reliably
            // persists resume state even for short play sessions.
            Task {
                let seconds = avPlayer?.currentTime().seconds
                let currentTicks: Int
                if let seconds, seconds.isFinite, seconds >= 0 {
                    currentTicks = SessionStore.secondsToTicks(seconds)
                } else {
                    currentTicks = lastKnownPositionTicks
                }

                let paused = avPlayer?.timeControlStatus != .playing
                if let context = playbackContext {
                    await session.reportPlaybackProgress(
                        context: context,
                        itemId: itemId,
                        positionTicks: max(currentTicks, lastKnownPositionTicks),
                        isPaused: paused
                    )
                }

                await reportPlaybackStopped(playedToCompletion: didPlayToEnd, failed: false)
            }
            detachPlayer()
        }
        .alert("Playback Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Close") {
                userInitiatedDismissal = true
                dismiss()
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }



    // MARK: - Jellyfin playback reporting

    private func attachPlayer(_ player: AVPlayer) {
        // Swap observers if the player instance changes (e.g., when switching to HLS).
        if avPlayer !== player {
            detachPlayer()
            avPlayer = player
        }

        guard timeObserverToken == nil else { return }

        // Capture an initial position as soon as the player is attached.
        let initialSeconds = player.currentTime().seconds
        if initialSeconds.isFinite, initialSeconds >= 0 {
            lastKnownPositionTicks = SessionStore.secondsToTicks(initialSeconds)
        }

        let interval = CMTime(seconds: 7, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
            let seconds = player.currentTime().seconds
            guard seconds.isFinite, seconds >= 0 else { return }

            let ticks = SessionStore.secondsToTicks(seconds)
            lastKnownPositionTicks = ticks

            // Avoid spamming: only report if we've advanced meaningfully.
            if abs(ticks - lastProgressReportTicks) < SessionStore.secondsToTicks(3) {
                return
            }
            lastProgressReportTicks = ticks

            let paused = player.timeControlStatus != .playing
            Task { await reportPlaybackProgress(positionTicks: ticks, isPaused: paused) }
        }

        // Subtitles availability can become known shortly after the item is created.
        // Refresh a couple times to catch late-bound HLS manifests.
        Task { @MainActor in
            refreshSubtitlesAvailability(for: player)
            try? await Task.sleep(nanoseconds: 600_000_000)
            refreshSubtitlesAvailability(for: player)
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            refreshSubtitlesAvailability(for: player)
        }
    }

    private func detachPlayer() {
        if let token = timeObserverToken, let player = avPlayer {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        avPlayer = nil
    }

    private func reportPlaybackStarted(initialTicks: Int) async {
        guard !hasReportedStart else { return }
        hasReportedStart = true
        guard let context = playbackContext else { return }

        // Keep our last-known position in sync.
        lastKnownPositionTicks = max(lastKnownPositionTicks, initialTicks)

        await session.reportPlaybackStarted(
            context: context,
            itemId: itemId,
            positionTicks: initialTicks,
            isPaused: false
        )
    }

    private func reportPlaybackProgress(positionTicks: Int, isPaused: Bool) async {
        guard let context = playbackContext else { return }
        await session.reportPlaybackProgress(
            context: context,
            itemId: itemId,
            positionTicks: positionTicks,
            isPaused: isPaused
        )
    }

    private func reportPlaybackStopped(playedToCompletion: Bool, failed: Bool) async {
        guard let context = playbackContext else { return }

        let seconds = avPlayer?.currentTime().seconds ?? 0
        let liveTicks = SessionStore.secondsToTicks(max(0, seconds))
        let ticks = max(liveTicks, lastKnownPositionTicks)

        await session.reportPlaybackStopped(
            context: context,
            itemId: itemId,
            positionTicks: ticks,
            playedToCompletion: playedToCompletion,
            failed: failed
        )
    }
    private var overlay: some View {
        HStack(spacing: 12) {
            if let posterURL {
                BBCachedAsyncImage(url: posterURL, targetSize: CGSize(width: 80, height: 80)) { phase in
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

            Button {
                toggleSubtitles()
                showOverlayNow()
            } label: {
                Text("CC")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(subtitlesEnabled ? .black : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if subtitlesEnabled {
                                Color.white
                            } else {
                                AnyShapeStyle(.ultraThinMaterial)
                            }
                        },
                        in: Capsule()
                    )
                    .opacity(subtitlesAvailable ? 1.0 : 0.35)
            }
            .disabled(!subtitlesAvailable)
            .accessibilityLabel(subtitlesEnabled ? "Disable Subtitles" : "Enable Subtitles")

            Button {
                userInitiatedDismissal = true
                dismiss()
            } label: {
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

    // MARK: - Subtitles / Closed Captions

    @MainActor
    private func refreshSubtitlesAvailability(for player: AVPlayer?) {
        guard let item = player?.currentItem else {
            subtitlesAvailable = false
            subtitlesEnabled = false
            return
        }

        let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        let options = group?.options ?? []
        let hasOptions = options.contains { !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        subtitlesAvailable = hasOptions

        // If subtitles were enabled but tracks disappeared (e.g., stream switch), disable.
        if !hasOptions {
            subtitlesEnabled = false
        }
    }

    @MainActor
    private func toggleSubtitles() {
        guard let item = avPlayer?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            subtitlesAvailable = false
            subtitlesEnabled = false
            return
        }

        let options = group.options
        let usableOptions = options.filter { !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        subtitlesAvailable = !usableOptions.isEmpty
        guard subtitlesAvailable else {
            subtitlesEnabled = false
            return
        }

        if subtitlesEnabled {
            // Disable subtitles.
            item.select(nil, in: group)
            subtitlesEnabled = false
            return
        }

        // Enable subtitles: try to pick a preferred option (matches the user's preferred languages) and fall back.
        let preferredLanguages = Locale.preferredLanguages
        let preferred = usableOptions.first(where: { opt in
            guard let locale = opt.locale else { return false }
            let id = locale.identifier.lowercased()
            return preferredLanguages.contains(where: { $0.lowercased().hasPrefix(id) })
        })

        let optionToSelect = preferred ?? usableOptions.first
        if let optionToSelect {
            item.select(optionToSelect, in: group)
            subtitlesEnabled = true
        } else {
            subtitlesEnabled = false
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

private 
struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let url: URL
    let startPositionTicks: Int

    let onPlayerReady: (AVPlayer) -> Void
    let onPlaybackStarted: (Int) -> Void
    let onPlaybackEnded: () -> Void

    let onUserInteraction: () -> Void
    let onPlaybackFailed: (Error?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onUserInteraction: onUserInteraction,
            onPlaybackFailed: onPlaybackFailed,
            onPlaybackEnded: onPlaybackEnded
        )
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        // Configure audio session early so playback and resume behavior are consistent.
        AudioSessionManager.shared.configureForPlaybackIfNeeded()

        let item = AVPlayerItem(url: url)
        // Favor fast start over aggressive buffering. This reduces the "delay
        // before first frame" effect on good connections.
        item.preferredForwardBufferDuration = 1

        let player = AVPlayer(playerItem: item)
        // Start promptly rather than waiting to buffer a large safety window.
        player.automaticallyWaitsToMinimizeStalling = false
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
#if !os(tvOS)
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
#endif

        controller.view.backgroundColor = .black

        context.coordinator.attachInteractionRecognizer(to: controller)
        context.coordinator.attach(to: player)

        onPlayerReady(player)
        startPlayback(on: player)

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if let current = (uiViewController.player?.currentItem?.asset as? AVURLAsset)?.url,
           current != url {
            AudioSessionManager.shared.configureForPlaybackIfNeeded()
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 1
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            uiViewController.player = player
            context.coordinator.attach(to: player)

            onPlayerReady(player)
            startPlayback(on: player)
        }
    }

    private func startPlayback(on player: AVPlayer) {
        if startPositionTicks > 0 {
            let seconds = Double(startPositionTicks) / 10_000_000.0
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            // Using zero tolerance can delay startup, especially for network streams.
            // Default tolerances are faster and still accurate for resume.
            player.seek(to: time) { _ in
                player.play()
                onPlaybackStarted(startPositionTicks)
            }
        } else {
            player.play()
            onPlaybackStarted(0)
        }
    }

    final class Coordinator: NSObject {
        private let onUserInteraction: () -> Void
        private let onPlaybackFailed: (Error?) -> Void
        private let onPlaybackEnded: () -> Void

        private var failedObserver: NSObjectProtocol?
        private var endedObserver: NSObjectProtocol?

        init(
            onUserInteraction: @escaping () -> Void,
            onPlaybackFailed: @escaping (Error?) -> Void,
            onPlaybackEnded: @escaping () -> Void
        ) {
            self.onUserInteraction = onUserInteraction
            self.onPlaybackFailed = onPlaybackFailed
            self.onPlaybackEnded = onPlaybackEnded
        }

        deinit {
            if let obs = failedObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = endedObserver { NotificationCenter.default.removeObserver(obs) }
        }

        func attach(to player: AVPlayer) {
            if let obs = failedObserver { NotificationCenter.default.removeObserver(obs); failedObserver = nil }
            if let obs = endedObserver { NotificationCenter.default.removeObserver(obs); endedObserver = nil }

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

                endedObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    self?.onPlaybackEnded()
                }
            }
        }

        func attachInteractionRecognizer(to controller: AVPlayerViewController) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
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


