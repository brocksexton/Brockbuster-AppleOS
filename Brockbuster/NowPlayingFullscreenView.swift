import SwiftUI
import AVKit
import AVFoundation

/// Fullscreen player UI driven by NowPlayingManager's AVPlayer.
/// Uses AVPlayerViewController so we get subtitles/audio selection and PiP.
struct NowPlayingFullscreenView: View {
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    @Environment(\.dismiss) private var dismiss

    @State private var overlayVisible: Bool = true
    @State private var overlayHideTask: Task<Void, Never>? = nil

    @State private var isScrubbing: Bool = false
    @State private var scrubProgress: Double = 0 // 0...1 while scrubbing

    @State private var upNextTick: Int = 0

    @State private var showingSubtitlesMenu: Bool = false
    @State private var showingQualityMenu: Bool = false

    @State private var showingRemoteSubtitles: Bool = false
    @State private var remoteSubtitleResults: [JellyfinClient.RemoteSubtitleInfo] = []
    @State private var remoteSubtitlesLoading: Bool = false
    @State private var remoteSubtitlesError: String? = nil

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
        VStack(spacing: 0) {
            topBar

            Spacer(minLength: 0)

            transportControls
        }
        .padding(.top, 10)
        .padding(.bottom, 18)
        .padding(.horizontal, 16)
        .ignoresSafeArea()
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.50), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button { showingSubtitlesMenu = true } label: {
                        Image(systemName: subtitlesEnabled ? "captions.bubble.fill" : "captions.bubble")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.50), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button { showingQualityMenu = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.50), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        nowPlaying.stop(playedToCompletion: false, failed: false)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.50), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            ticketHeader
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.26),
                        Color.yellow.opacity(0.14),
                        Color.black.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
        }
        .confirmationDialog("Subtitles", isPresented: $showingSubtitlesMenu, titleVisibility: .visible) {
            subtitleDialogButtons
        }
        .confirmationDialog("Quality", isPresented: $showingQualityMenu, titleVisibility: .visible) {
            qualityDialogButtons
        }
        .sheet(isPresented: $showingRemoteSubtitles) {
            RemoteSubtitlesSheet(
                title: headerPrimaryTitle,
                isLoading: remoteSubtitlesLoading,
                errorMessage: remoteSubtitlesError,
                results: remoteSubtitleResults,
                onRefresh: { Task { await fetchRemoteSubtitles() } },
                onDownload: { sub in Task { await downloadRemoteSubtitle(sub) } }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var headerPrimaryTitle: String {
        guard let item = nowPlaying.item else { return "" }
        if item.mediaKind == .episode {
            return item.seriesTitle ?? item.title
        }
        return item.title
    }

    private var headerSecondaryTitle: String? {
        guard let item = nowPlaying.item else { return nil }
        if item.mediaKind == .episode {
            var parts: [String] = []
            if let s = item.seasonNumber { parts.append("S\(s)") }
            if let e = item.episodeNumber { parts.append("E\(e)") }
            let se = parts.joined(separator: " • ")
            let epTitle = item.episodeTitle ?? item.title
            if se.isEmpty { return epTitle }
            return "\(se) • \(epTitle)"
        }
        return item.subtitle
    }

    private var ticketHeader: some View {
        HStack(spacing: 12) {
            // Poster / season art (if provided)
            if let poster = nowPlaying.item?.posterURL {
                BBCachedAsyncImage(url: poster) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.white.opacity(0.06)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 7)
            } else if let logoURL = nowPlaying.logoURL(maxWidth: 600) {
                BBCachedAsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        EmptyView()
                    }
                }
                .frame(width: 56, height: 56)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Prefer a Jellyfin Logo image if available.
                    if let logoURL = nowPlaying.logoURL(maxWidth: 900) {
                        BBCachedAsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                            default:
                                Text(headerPrimaryTitle)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(height: 26)
                        .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 5)
                    } else {
                        Text(headerPrimaryTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 5)
                    }

                    Spacer(minLength: 0)
                }

                if let secondary = headerSecondaryTitle, !secondary.isEmpty {
                    Text(secondary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(
            // Ticket notch cues
            HStack {
                Circle().fill(Color.black.opacity(0.22)).frame(width: 10, height: 10)
                Spacer()
                Circle().fill(Color.black.opacity(0.22)).frame(width: 10, height: 10)
            }
            .padding(.horizontal, 10)
        )
    }

    private var transportControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 26) {
                Button { seekRelative(-10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(.black.opacity(0.40), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button { nowPlaying.togglePlayPause() } label: {
                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.black.opacity(0.50), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button { seekRelative(10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(.black.opacity(0.40), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubProgress : nowPlaying.progress },
                        set: { newValue in
                            scrubProgress = newValue
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            seekToProgress(scrubProgress)
                            scheduleOverlayAutoHide()
                        } else {
                            overlayHideTask?.cancel()
                        }
                    }
                )

                HStack {
                    Text(formatTime(currentSeconds))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()

                    Spacer()

                    Text("-")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))

                    Text(formatTime(max(0, durationSeconds - currentSeconds)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
        }
    }

    private var currentSeconds: Double {
        SessionStore.ticksToSeconds(nowPlaying.currentPositionTicks)
    }

    private var durationSeconds: Double {
        if let seconds = nowPlaying.currentPlayer()?.currentItem?.duration.seconds,
           seconds.isFinite, seconds > 0 {
            return seconds
        }
        return 0
    }

    private func seekRelative(_ delta: Double) {
        guard durationSeconds > 0 else { return }
        // Use the live AVPlayer clock to avoid stale tick updates causing
        // smaller-than-expected skips.
        let base = nowPlaying.currentPlayer()?.currentTime().seconds
        let current = (base?.isFinite == true) ? (base ?? currentSeconds) : currentSeconds
        let next = max(0, min(durationSeconds, current + delta))
        nowPlaying.seek(to: next)
        scheduleOverlayAutoHide()
    }

    private func seekToProgress(_ progress: Double) {
        guard durationSeconds > 0 else { return }
        let clamped = max(0, min(1, progress))
        nowPlaying.seek(to: durationSeconds * clamped)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Subtitles / Quality

    private var subtitleOptions: [AVMediaSelectionOption] {
        guard let item = nowPlaying.currentPlayer()?.currentItem else { return [] }
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return [] }
        return group.options
    }

    private var subtitlesEnabled: Bool {
        guard let item = nowPlaying.currentPlayer()?.currentItem else { return false }
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return false }
        return item.currentMediaSelection.selectedMediaOption(in: group) != nil
    }

    @ViewBuilder
    private var subtitleDialogButtons: some View {
        Button("Off") {
            selectSubtitle(nil)
            scheduleOverlayAutoHide()
        }

        if subtitleOptions.isEmpty {
            Button("Find Subtitles…") {
                showingRemoteSubtitles = true
                Task { await fetchRemoteSubtitles() }
            }

            Button("No subtitles currently attached") {}
                .disabled(true)
        } else {
            ForEach(Array(subtitleOptions.enumerated()), id: \.offset) { _, opt in
                Button(opt.displayName) {
                    selectSubtitle(opt)
                    scheduleOverlayAutoHide()
                }
            }
        }

        Button("Cancel", role: .cancel) {}
    }

    private func selectSubtitle(_ option: AVMediaSelectionOption?) {
        guard let item = nowPlaying.currentPlayer()?.currentItem else { return }
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        item.select(option, in: group)
    }

    @ViewBuilder
    private var qualityDialogButtons: some View {
        ForEach(NowPlayingManager.QualityOption.allCases) { opt in
            Button {
                nowPlaying.setQuality(opt)
                scheduleOverlayAutoHide()
            } label: {
                if nowPlaying.quality == opt {
                    Label(opt.title, systemImage: "checkmark")
                } else {
                    Text(opt.title)
                }
            }
        }
        Button("Cancel", role: .cancel) {}
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
                          nowPlaying.currentPlayer() != nil else { return }
                    let seconds = SessionStore.ticksToSeconds(window.endTicks)
                    nowPlaying.seek(to: seconds)
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
                .padding(.bottom, 140) // keep above custom transport controls
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
    // MARK: - Remote subtitle helpers

    @MainActor
    private func fetchRemoteSubtitles() async {
        remoteSubtitlesLoading = true
        remoteSubtitlesError = nil
        remoteSubtitleResults = []
        do {
            let res = try await nowPlaying.fetchRemoteSubtitles()
            remoteSubtitleResults = res
            if res.isEmpty {
                remoteSubtitlesError = "No remote subtitles found."
            }
        } catch {
            remoteSubtitlesError = "Failed to search subtitles: \(error.localizedDescription)"
        }
        remoteSubtitlesLoading = false
    }

    @MainActor
    private func downloadRemoteSubtitle(_ remote: JellyfinClient.RemoteSubtitleInfo) async {
        remoteSubtitlesLoading = true
        remoteSubtitlesError = nil
        do {
            try await nowPlaying.downloadRemoteSubtitle(remote)
            remoteSubtitlesError = "Downloaded. Reloading tracks…"
            // Give the server a brief moment to finalize the attachment.
            try? await Task.sleep(nanoseconds: 450_000_000)
            showingRemoteSubtitles = false
        } catch {
            remoteSubtitlesError = "Failed to download subtitle: \(error.localizedDescription)"
        }
        remoteSubtitlesLoading = false
    }
}

struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        #if os(tvOS)
        // Keep native controls on tvOS for best focus/remote ergonomics.
        vc.showsPlaybackControls = true
        #else
        // iOS/iPadOS: we provide a fully custom overlay UI.
        vc.showsPlaybackControls = false
        #endif
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
