import SwiftUI
import AVKit
import AVFoundation

/// Fullscreen player UI driven by NowPlayingManager's AVPlayer.
/// Uses AVPlayerViewController so we get subtitles/audio selection and PiP.
struct NowPlayingFullscreenView: View {
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    @EnvironmentObject private var castManager: CastManager
    @Environment(\.dismiss) private var dismiss

    @State private var overlayVisible: Bool = true
    @State private var overlayHideTask: Task<Void, Never>? = nil

    @State private var isScrubbing: Bool = false
    @State private var scrubProgress: Double = 0 // 0...1 while scrubbing

    @State private var upNextTick: Int = 0

    @State private var showingSubtitlesMenu: Bool = false
    @State private var showingQualityMenu: Bool = false
    @State private var showingCastSheet: Bool = false

    @State private var showingVirtualRemote: Bool = false
    @StateObject private var routeMonitor = RemoteRouteMonitor()

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
                    .allowsHitTesting(false)
            } else {
                Color.black
                    .ignoresSafeArea()
                    .onTapGesture { handleToggleOverlay() }
            }

            // Tap catcher for toggling our overlay (player view has interactions disabled).
            // Placed above the video but below controls so buttons/sliders still work.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { handleToggleOverlay() }


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
        .sheet(isPresented: $showingCastSheet) {
            CastSheetView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingVirtualRemote) {
            VirtualRemoteSheet(
                isPresented: $showingVirtualRemote,
                connectedName: connectedTargetName,
                providerLabel: connectedProviderLabel
            )
            .presentationDetents([.medium, .large])
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
        .onChange(of: nowPlaying.item?.id) { _ in
            // When autoplay advances to the next episode, ensure our scrubber state
            // resets so the slider immediately reflects the new item.
            isScrubbing = false
            scrubProgress = 0
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
                    if isRemoteConnected {
                        Button { showingVirtualRemote = true } label: {
                            Image(systemName: "tv.remote")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.black.opacity(0.50), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remote")
                    }

                    Button { showingCastSheet = true } label: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.50), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

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
                        VStack(alignment: .leading, spacing: 2) {
                            BBCachedAsyncImage(url: logoURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                default:
                                    // If the logo fails to load, fall back immediately to text.
                                    Text(headerPrimaryTitle)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(height: 26)
                            .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 5)

                            // Always show the title as well so playback context is never “blank”.
                            Text(headerPrimaryTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                        }
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
#if !os(tvOS)
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
#endif

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
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.85)
                        .allowsTightening(true)

                    Text(remaining > 0 ? "Playing in \(remaining)s" : "Playing now")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .dynamicTypeSize(.xSmall ... .xxxLarge)

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
            // If a modal/menu is open, keep the overlay visible. Users should not
            // lose access to dismissal controls while interacting with a sheet/
            // dialog.
            if showingCastSheet || showingSubtitlesMenu || showingQualityMenu || showingRemoteSubtitles || showingVirtualRemote {
                overlayVisible = true
                return
            }
            withAnimation(.easeInOut(duration: 0.20)) {
                overlayVisible = false
            }
        }
    }

    private var isRemoteConnected: Bool {
        if castManager.connectedDevice != nil { return true }
        return routeMonitor.isAirPlayActive
    }

    private var connectedTargetName: String {
        if let device = castManager.connectedDevice {
            return device.name
        }
        if let route = routeMonitor.routeName {
            return route
        }
        return "This Device"
    }

    private var connectedProviderLabel: String {
        if let device = castManager.connectedDevice {
            switch device.provider {
            case .googleCast: return "Chromecast"
            case .roku: return "Roku"
            case .dlna: return "DLNA"
            case .airPlay: return "AirPlay"
            case .brockbusterReceiver: return "Brockbuster"
            }
        }
        return routeMonitor.isAirPlayActive ? "AirPlay" : "Local"
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
        vc.view.isUserInteractionEnabled = false
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

// MARK: - Virtual TV Remote

/// Lightweight monitor for whether the current audio route is using AirPlay.
/// We use this to conditionally show the Virtual Remote button.
final class RemoteRouteMonitor: ObservableObject {
    @Published private(set) var isAirPlayActive: Bool = false
    @Published private(set) var routeName: String? = nil

    private var tokens: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        })
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        })
    }

    deinit {
        for t in tokens { NotificationCenter.default.removeObserver(t) }
    }

    private func refresh() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let airPlayOutput = route.outputs.first(where: { $0.portType == .airPlay })
        isAirPlayActive = (airPlayOutput != nil)
        routeName = airPlayOutput?.portName
    }
}

private enum VirtualRemoteTheme: String, CaseIterable, Identifiable {
    case glass
    case blockbuster
    case minimal

    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: return "Glass"
        case .blockbuster: return "Blockbuster"
        case .minimal: return "Minimal"
        }
    }
}

/// A professional, sleek remote control sheet that stays open independently of
/// the player's auto-hiding overlay. This primarily controls the local AVPlayer
/// (including when routed via AirPlay). Provider-specific deep controls can be
/// added later (Chromecast/Roku/DLNA).
struct VirtualRemoteSheet: View {
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    @EnvironmentObject private var castManager: CastManager

    @Binding var isPresented: Bool
    let connectedName: String
    let providerLabel: String

    @AppStorage("remote.theme") private var storedTheme: String = VirtualRemoteTheme.glass.rawValue
    @AppStorage("remote.buttonScale") private var buttonScale: Double = 1.0
    @AppStorage("remote.skipBackSeconds") private var skipBackSeconds: Double = 10
    @AppStorage("remote.skipForwardSeconds") private var skipForwardSeconds: Double = 30

    @State private var showingCustomize: Bool = false
    @State private var localScrub: Double = 0
    @State private var isScrubbing: Bool = false

    private var theme: VirtualRemoteTheme {
        VirtualRemoteTheme(rawValue: storedTheme) ?? .glass
    }

    private var player: AVPlayer? { nowPlaying.currentPlayer() }

    private var durationSeconds: Double {
        guard let d = player?.currentItem?.duration.seconds, d.isFinite, d > 0 else { return 0 }
        return d
    }

    private var currentSeconds: Double {
        SessionStore.ticksToSeconds(nowPlaying.currentPositionTicks)
    }

    private var isPlaying: Bool {
        nowPlaying.isPlaying
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                header
                scrubber
                transportGrid
                quickActions
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(background)
            .navigationTitle("Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingCustomize.toggle()
                    } label: {
                        Image(systemName: "paintbrush")
                    }
                    .accessibilityLabel("Customize remote")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresented = false
                    } label: {
                        Text("Done").font(.body.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showingCustomize) {
                customizeSheet
            }
            .onAppear {
                localScrub = nowPlaying.progress
            }
            .onChange(of: nowPlaying.progress) { newValue in
                guard !isScrubbing else { return }
                localScrub = newValue
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(.black.opacity(theme == .minimal ? 0.12 : 0.30))
                Image(systemName: providerIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(themeAccent)
            }
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(.white.opacity(theme == .minimal ? 0.10 : 0.14), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(connectedName)
                    .font(.headline)
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                Text(providerLabel)
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if castManager.connectedDevice != nil {
                Button(role: .destructive) {
                    castManager.disconnect()
                } label: {
                    Text("Disconnect")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(theme == .minimal ? 0.10 : 0.12), lineWidth: 1))
    }

    private var scrubber: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { localScrub },
                    set: { newValue in
                        localScrub = newValue
                        isScrubbing = true
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing {
                        isScrubbing = false
                        let target = durationSeconds * localScrub
                        nowPlaying.seek(to: target)
                    }
                }
            )

            HStack {
                Text(timeString(currentSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(secondaryText)
                Spacer()
                Text(timeString(max(0, durationSeconds - currentSeconds)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(secondaryText)
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(theme == .minimal ? 0.10 : 0.12), lineWidth: 1))
    }

    private var transportGrid: some View {
        HStack(spacing: 12) {
            remoteButton(icon: "gobackward", label: "Back") {
                skip(by: -skipBackSeconds)
            }
            remoteButton(icon: isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Play", isPrimary: true) {
                togglePlayPause()
            }
            remoteButton(icon: "goforward", label: "Forward") {
                skip(by: skipForwardSeconds)
            }
        }
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                infoPill(title: "Skip", value: "\(Int(skipBackSeconds))s / \(Int(skipForwardSeconds))s")
                infoPill(title: "Speed", value: playbackRateLabel)
            }

            HStack(spacing: 12) {
                remoteSmallButton(icon: "speedometer", title: "Speed") {
                    cyclePlaybackRate()
                }
                remoteSmallButton(icon: "speaker.wave.2", title: "Mute") {
                    toggleMute()
                }
                remoteSmallButton(icon: "stop.fill", title: "Stop") {
                    nowPlaying.stop(playedToCompletion: false, failed: false)
                }
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(theme == .minimal ? 0.10 : 0.12), lineWidth: 1))
    }

    private var customizeSheet: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $storedTheme) {
                        ForEach(VirtualRemoteTheme.allCases) { t in
                            Text(t.title).tag(t.rawValue)
                        }
                    }
                    Slider(value: $buttonScale, in: 0.85...1.25, step: 0.05) {
                        Text("Button size")
                    }
                    Text("Tip: Glass looks best with Brockbuster’s player overlay. Minimal is great for readability.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Controls") {
                    Stepper("Skip back: \(Int(skipBackSeconds))s", value: $skipBackSeconds, in: 5...60, step: 5)
                    Stepper("Skip forward: \(Int(skipForwardSeconds))s", value: $skipForwardSeconds, in: 10...120, step: 5)
                }
            }
            .navigationTitle("Customize Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingCustomize = false }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Styling

    private var providerIcon: String {
        switch providerLabel.lowercased() {
        case let s where s.contains("airplay"): return "airplayvideo"
        case let s where s.contains("chromecast"): return "dot.radiowaves.left.and.right"
        case let s where s.contains("roku"): return "tv"
        case let s where s.contains("dlna"): return "tv.and.hifispeaker.fill"
        default: return "tv"
        }
    }

    private var themeAccent: Color {
        switch theme {
        case .glass: return .white
        case .blockbuster: return Color(red: 1.0, green: 0.67, blue: 0.04) // Brockbuster gold-ish
        case .minimal: return .primary
        }
    }

    private var primaryText: Color {
        theme == .minimal ? .primary : .white
    }

    private var secondaryText: Color {
        theme == .minimal ? .secondary : .white.opacity(0.72)
    }

    private var background: some View {
        Group {
            switch theme {
            case .minimal:
                Color(.systemBackground)
            case .blockbuster:
                LinearGradient(
                    colors: [Color(red: 0.06, green: 0.25, blue: 0.66), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .glass:
                LinearGradient(
                    colors: [Color.black.opacity(0.88), Color.black.opacity(0.70)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }

    private var cardBackground: some ShapeStyle {
        switch theme {
        case .minimal:
            return AnyShapeStyle(Color(.secondarySystemBackground))
        case .blockbuster:
            return AnyShapeStyle(Color.black.opacity(0.35))
        case .glass:
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private func remoteButton(icon: String, label: String, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        let size: CGFloat = 70 * buttonScale
        return Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: isPrimary ? 22 : 20, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isPrimary ? Color.black : primaryText)
            .frame(width: size, height: size)
            .background(isPrimary ? themeAccent : Color.black.opacity(theme == .minimal ? 0.08 : 0.30), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(theme == .minimal ? 0.10 : 0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func remoteSmallButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.black.opacity(theme == .minimal ? 0.06 : 0.25), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(theme == .minimal ? 0.10 : 0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func infoPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(theme == .minimal ? 0.06 : 0.25), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(theme == .minimal ? 0.10 : 0.12), lineWidth: 1))
    }

    // MARK: - Control actions

    private func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    private func skip(by delta: Double) {
        guard durationSeconds > 0 else { return }
        let target = min(max(0, currentSeconds + delta), durationSeconds)
        nowPlaying.seek(to: target)
    }

    private var playbackRateLabel: String {
        let rate = player?.rate ?? 1.0
        if abs(rate - 1.0) < 0.01 { return "1.0×" }
        return String(format: "%.2g×", rate)
    }

    private func cyclePlaybackRate() {
        guard let player else { return }
        let current = player.rate
        // Cycle: 1.0 -> 1.25 -> 1.5 -> 2.0 -> 1.0
        let next: Float
        if current < 1.1 { next = 1.25 }
        else if current < 1.3 { next = 1.5 }
        else if current < 1.75 { next = 2.0 }
        else { next = 1.0 }

        if isPlaying {
            player.rate = next
        } else {
            // Rate change doesn't always persist while paused; store as preferred by playing briefly is not desirable.
            // Best-effort: set and keep paused.
            player.rate = next
        }
    }

    private func toggleMute() {
        guard let player else { return }
        player.isMuted.toggle()
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
