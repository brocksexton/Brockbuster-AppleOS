import SwiftUI

/// Traditional TV series view:
/// - Header with show artwork + metadata
/// - Season selector
/// - Episode list for selected season (with optional episode search)
struct SeriesDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    let series: JellyfinClient.LibraryItem

    @State private var details: JellyfinClient.ItemDetail?
    @State private var seasons: [JellyfinClient.LibraryItem] = []
    @State private var selectedSeason: JellyfinClient.LibraryItem?
    @State private var episodes: [JellyfinClient.LibraryItem] = []

    @State private var primaryEpisode: JellyfinClient.LibraryItem?
    @State private var primaryActionTitle: String = "Play"
    @State private var primaryActionSubtitle: String? = nil

    @State private var isLoading = true
    @State private var isLoadingEpisodes = false
    @State private var errorMessage: String?

    @State private var favoriteOverride: Bool? = nil
    @State private var isTogglingFavorite: Bool = false
    
    // Playback is handled by NowPlayingManager so playback persists if the user
    // dismisses the fullscreen player.

    @State private var episodeQuery = ""

    /// Tracks per-season watch progress so we can add UI indicators in the season picker.
    @State private var seasonWatchStates: [String: SeasonWatchState] = [:]

    private var filteredEpisodes: [JellyfinClient.LibraryItem] {
        let q = episodeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return episodes }
        return episodes.filter { ($0.name).localizedCaseInsensitiveContains(q) }
    }

    private var isFavorite: Bool {
        if let o = favoriteOverride { return o }
        return details?.userData?.isFavorite ?? series.userData?.isFavorite ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let errorMessage {
                    GlassCard {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if !seasons.isEmpty {
                    seasonPicker
                }

                episodesSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(BrockbusterTheme.Background)
        .navigationTitle(series.name ?? "Show")
        .bbNavigationTitleInline()
        .task { await load() }
    }

    // MARK: - UI


private var primaryPlayRow: some View {
    HStack(spacing: 10) {
        Button {
            Task { await playPrimary() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryActionTitle)
                        .font(.subheadline.weight(.semibold))
                    if let sub = primaryActionSubtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.black.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(.black)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrockbusterTheme.ticketYellow)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(primaryEpisode == nil && isLoading)

        Button {
            // Jump user down to episodes; the season list is already visible.
            withAnimation(.easeInOut(duration: 0.25)) {
                // no-op; kept for future anchor scroll
            }
        } label: {
            Image(systemName: "list.bullet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrockbusterTheme.textPrimary)
                .padding(12)
                .background(.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse episodes")
    }
}


    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                PosterImage(item: series, kind: .poster)
                    .frame(width: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text(details?.name ?? series.name ?? "")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(BrockbusterTheme.textPrimary)

                    HStack(spacing: 8) {
                        if let year = (details?.productionYear ?? series.productionYear) {
                            Text(String(year))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(BrockbusterTheme.textSecondary)
                    .lineLimit(1)

                    if let overview = details?.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.subheadline)
                            .foregroundStyle(BrockbusterTheme.textSecondary)
                            .lineLimit(4)
                    }

                    primaryPlayRow

                    HStack(spacing: 10) {
                        if let season = selectedSeason {
                            InfoPill(text: seasonDisplayName(season))
                        }
                        if isLoading {
                            InfoPill(text: "Loading…", icon: "sparkles")
                        }
                    }
                }

                Spacer(minLength: 0)

                Button {
                    Task { await toggleFavoriteSeries() }
                } label: {
                    ZStack {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isFavorite ? BrockbusterTheme.ticketYellow : BrockbusterTheme.textPrimary)

                        if isTogglingFavorite {
                            ProgressView()
                                .scaleEffect(0.75)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTogglingFavorite || details == nil)
            }
        }
        .padding(.top, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.35), value: details?.id)
    }

    private var seasonPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Seasons")
                .font(.headline)
                .foregroundStyle(BrockbusterTheme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(seasons, id: \.id) { season in
                        let isSelected = season.id == selectedSeason?.id
                        let watchState = seasonWatchStates[season.id] ?? .none
                        SeasonPill(
                            title: seasonDisplayName(season),
                            isSelected: isSelected,
                            watchState: watchState,
                            action: { Task { await selectSeason(season) } }
                        )
                        .accessibilityLabel(seasonDisplayName(season))
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: seasons.count)
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Episodes")
                    .font(.headline)
                    .foregroundStyle(BrockbusterTheme.textPrimary)
                Spacer()
                if isLoadingEpisodes {
                    ProgressView()
                        .tint(BrockbusterTheme.ticketYellow)
                }
            }

            // Episode search is scoped to the currently selected season.
            if selectedSeason != nil {
                #if os(tvOS)
                TextField("Search episodes", text: $episodeQuery)
                    .autocorrectionDisabled(true)
                #else
                TextField("Search episodes", text: $episodeQuery)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                #endif
            }

            if selectedSeason == nil {
                GlassCard {
                    Text("No seasons found for this show.")
                        .foregroundStyle(BrockbusterTheme.textSecondary)
                }
            } else if filteredEpisodes.isEmpty {
                GlassCard {
                    Text(isLoadingEpisodes ? "Loading episodes…" : "No episodes found.")
                        .foregroundStyle(BrockbusterTheme.textSecondary)
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredEpisodes) { ep in
                        NavigationLink {
                            ItemDetailView(item: ep)
                                .environmentObject(session)
                        } label: {
                            EpisodeRow(episode: ep, seriesFallback: series) { await play(episode: ep) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        errorMessage = nil

        do {
            async let d = session.fetchItemDetails(itemId: series.id)
            async let s = session.fetchItems(
                for: series,
                includeItemTypes: ["Season"],
                sortBy: ["ParentIndexNumber", "IndexNumber", "SortName"],
                sortOrder: "Ascending"
            )

            let (detailsResult, seasonsResult) = try await (d, s)
            details = detailsResult

            // Jellyfin sometimes returns “Specials” with index 0. Keep it; order
            // will place it first.
            seasons = seasonsResult
                .filter { $0.type?.lowercased() == "season" || $0.name != nil }

            // Pre-compute watch progress indicators for the season picker.
            // This runs in the background and will update the UI as results come in.
            Task { await computeSeasonWatchStatesIfNeeded() }

            // Resolve primary play action (Resume / Next Episode / Play)
            do {
                if let nextUp = try await session.fetchNextUpEpisode(seriesId: series.id) {
                    primaryEpisode = nextUp
                    let pos = nextUp.userData?.playbackPositionTicks ?? 0
                    let played = nextUp.userData?.played ?? false
                    if pos > 0 && !played {
                        primaryActionTitle = "Resume"
                    } else {
                        primaryActionTitle = "Next Episode"
                    }
                    primaryActionSubtitle = episodeSubtitle(for: nextUp)
                } else {
                    primaryEpisode = nil
                    primaryActionTitle = "Play"
                    primaryActionSubtitle = nil
                }
            } catch {
                // If NextUp fails, continue with normal season/episode browsing.
                primaryEpisode = nil
                primaryActionTitle = "Play"
                primaryActionSubtitle = nil
            }

            if selectedSeason == nil {
                selectedSeason = seasons.first
            }

            if let selectedSeason {
                await selectSeason(selectedSeason)
                // Fallback primary episode to the first episode of the first season.
                if primaryEpisode == nil {
                    primaryEpisode = episodes.first
                    if let ep = primaryEpisode { primaryActionSubtitle = episodeSubtitle(for: ep) }
                }
            }
        } catch {
            errorMessage = "Unable to load show details. \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Favorites

    @MainActor
    private func toggleFavoriteSeries() async {
        guard details != nil else { return }
        guard session.currentUser != nil else { return }

        let newValue = !isFavorite
        isTogglingFavorite = true
        favoriteOverride = newValue

        do {
            try await session.setFavorite(itemId: series.id, isFavorite: newValue)
            favoriteOverride = nil
            // Refresh details so the UI stays in sync.
            do {
                details = try await session.fetchItemDetails(itemId: series.id)
            } catch {
                // Non-fatal; keep optimistic state.
            }
        } catch {
            favoriteOverride = nil
            errorMessage = error.localizedDescription
        }

        isTogglingFavorite = false
    }

    private func selectSeason(_ season: JellyfinClient.LibraryItem) async {
        selectedSeason = season
        episodeQuery = ""
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }

        do {
            episodes = try await session.fetchItems(
                for: season,
                includeItemTypes: ["Episode"],
                sortBy: ["ParentIndexNumber", "IndexNumber", "SortName"],
                sortOrder: "Ascending"
            )
            .filter { $0.type?.lowercased() == "episode" }

            // Update season watch state based on the newly loaded episodes.
            updateSeasonWatchState(seasonId: season.id, episodes: episodes)
        } catch {
            episodes = []
            errorMessage = "Unable to load episodes. \(error.localizedDescription)"
        }
    }

    /// Derive a season's watch state from episode `UserData`.
    private func updateSeasonWatchState(seasonId: String, episodes: [JellyfinClient.LibraryItem]) {
        guard !episodes.isEmpty else {
            seasonWatchStates[seasonId] = .none
            return
        }

        let playedCount = episodes.filter { $0.userData?.played == true }.count
        let inProgressCount = episodes.filter {
            let played = $0.userData?.played ?? false
            let pos = $0.userData?.playbackPositionTicks ?? 0
            return !played && pos > 0
        }.count

        if playedCount == episodes.count {
            seasonWatchStates[seasonId] = .complete
        } else if playedCount > 0 || inProgressCount > 0 {
            seasonWatchStates[seasonId] = .partial
        } else {
            seasonWatchStates[seasonId] = .none
        }
    }

    /// Best-effort background computation of season watch indicators.
    /// This intentionally avoids re-fetching seasons that have already been computed.
    private func computeSeasonWatchStatesIfNeeded() async {
        // If the view is still loading, we may not have seasons yet.
        guard !seasons.isEmpty else { return }

        for season in seasons {
            if seasonWatchStates[season.id] != nil { continue }

            do {
                let eps = try await session.fetchItems(
                    for: season,
                    includeItemTypes: ["Episode"],
                    sortBy: ["ParentIndexNumber", "IndexNumber", "SortName"],
                    sortOrder: "Ascending"
                )
                .filter { $0.type?.lowercased() == "episode" }

                updateSeasonWatchState(seasonId: season.id, episodes: eps)
            } catch {
                // Non-fatal: show no indicator for this season.
                seasonWatchStates[season.id] = .none
            }
        }
    }

    /// After playback, refresh the current season and Next Up to update watched indicators.
    private func refreshWatchStateAfterPlayback() async {
        // Refresh Next Up / Resume button label.
        do {
            if let nextUp = try await session.fetchNextUpEpisode(seriesId: series.id) {
                primaryEpisode = nextUp
                let pos = nextUp.userData?.playbackPositionTicks ?? 0
                let played = nextUp.userData?.played ?? false
                if pos > 0 && !played {
                    primaryActionTitle = "Resume"
                } else {
                    primaryActionTitle = "Next Episode"
                }
                primaryActionSubtitle = episodeSubtitle(for: nextUp)
            }
        } catch {
            // Ignore; player dismissal should not surface a new error state.
        }

        if let season = selectedSeason {
            await selectSeason(season)
        }

        // Fill in missing season states opportunistically.
        await computeSeasonWatchStatesIfNeeded()
    }


private func playPrimary() async {
    // Prefer resolved primary episode; otherwise fall back to first visible episode.
    if let ep = primaryEpisode {
        await play(episode: ep)
        return
    }
    if let ep = filteredEpisodes.first {
        await play(episode: ep)
    }
}

    private func episodeSubtitle(for ep: JellyfinClient.LibraryItem) -> String {
        var parts: [String] = []
        if let s = ep.parentIndexNumber, s > 0 { parts.append("S\(s)") }
        if let e = ep.indexNumber, e > 0 { parts.append("E\(e)") }
        let se = parts.joined(separator: "")
        let name = ep.name ?? ""
        if se.isEmpty { return name }
        if !name.isEmpty {
            return "\(se) • \(name)"
        }
        return se
    }

    private func seasonDisplayName(_ season: JellyfinClient.LibraryItem) -> String {
        if let index = season.indexNumber {
            return index == 0 ? "Specials" : "Season \(index)"
        }
        return season.name
    }
    
    private func play(episode: JellyfinClient.LibraryItem) async {
        guard !isLoadingEpisodes else { return }
        await MainActor.run {
            primaryActionSubtitle = episodeSubtitle(for: episode)
            nowPlaying.play(
                itemId: episode.id,
                title: details?.name ?? series.name ?? "",
                subtitle: primaryActionSubtitle,
                posterURL: session.itemImageURL(for: series, maxWidth: 700),
                startPositionTicks: episode.userData?.playbackPositionTicks ?? 0,
                mediaKind: .episode,
                seriesIdForEpisode: episode.seriesId ?? series.id,
                seriesTitle: details?.name ?? series.name,
                seasonNumber: episode.parentIndexNumber,
                episodeNumber: episode.indexNumber,
                episodeTitle: episode.name,
                session: session
            )
        }
    }
}

/// Per-season watch progress.
private enum SeasonWatchState: Equatable {
    case none
    case partial
    case complete
}

private struct SeasonPill: View {
    let title: String
    let isSelected: Bool
    let watchState: SeasonWatchState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .black : BrockbusterTheme.textPrimary)

                if let symbol = watchSymbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isSelected ? .black.opacity(0.85) : BrockbusterTheme.ticketYellow)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(backgroundStyle)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(.white.opacity(isSelected ? 0 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var watchSymbol: String? {
        switch watchState {
        case .none:
            return nil
        case .partial:
            return "circle.dashed"
        case .complete:
            return "checkmark.circle.fill"
        }
    }

    private var backgroundStyle: some ShapeStyle {
        if isSelected {
            return BrockbusterTheme.ticketYellow
        } else {
            return .white.opacity(0.10)
        }
    }
}

private struct InfoPill: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(BrockbusterTheme.ticketYellow)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(.white.opacity(0.0), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

private struct EpisodeRow: View {
    let episode: JellyfinClient.LibraryItem
    let seriesFallback: JellyfinClient.LibraryItem?
    var onPlay: (() async -> Void)? = nil

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {

                HStack(spacing: 12) {
                    // Thumbnail + progress bar under it
                    VStack(alignment: .leading, spacing: 6) {
                        PosterImage(item: episode, kind: .thumb, fallbackItem: seriesFallback)
                            .frame(width: 110, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.10), lineWidth: 1)
                            )

                        if let progress = watchProgressFraction {
                            EpisodeProgressBar(progress: progress)
                                .frame(width: 110)
                                .accessibilityLabel("Playback progress")
                                .accessibilityValue("\(Int(progress * 100)) percent")
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(episodeTitle(episode))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrockbusterTheme.textPrimary)
                            .lineLimit(2)

                        if let overview = episode.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.caption)
                                .foregroundStyle(BrockbusterTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)

                    // Watched / in-progress indicator (per-user)
                    if let indicator = watchIndicatorSymbol {
                        Image(systemName: indicator)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(watchIndicatorStyle)
                            .accessibilityLabel(watchIndicatorA11yLabel)
                    }

                    if let onPlay {
                        Button(action: { Task { await onPlay() } }) {
                            Image(systemName: "play.fill")
                                .font(.body.weight(.bold))
                                .foregroundStyle(BrockbusterTheme.ticketYellow)
                                .padding(8)
                                .background(.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    // MARK: - Watch State + Progress

    /// Returns 0.0...1.0 for in-progress playback, or nil when we should not show a bar.
    private var watchProgressFraction: Double? {
        let played = episode.userData?.played ?? false
        if played { return 1.0 }

        let pos = Double(episode.userData?.playbackPositionTicks ?? 0)
        guard pos > 0 else { return nil }

        // runtimeTicks is the most reliable; if missing, hide the bar to avoid incorrect UI.
        let runtime = Double(episode.runtimeTicks ?? 0)
        guard runtime > 0 else { return nil }

        let frac = pos / runtime
        // Avoid rendering full bar unless actually marked played; cap at 0.995.
        return max(0.0, min(frac, 0.995))
    }

    private var watchIndicatorSymbol: String? {
        let played = episode.userData?.played ?? false
        let pos = episode.userData?.playbackPositionTicks ?? 0
        if played { return "checkmark.circle.fill" }
        if pos > 0 { return "clock.fill" }
        return nil
    }

    private var watchIndicatorStyle: some ShapeStyle {
        let played = episode.userData?.played ?? false
        return played ? BrockbusterTheme.ticketYellow : .white.opacity(0.70)
    }

    private var watchIndicatorA11yLabel: String {
        let played = episode.userData?.played ?? false
        let pos = episode.userData?.playbackPositionTicks ?? 0
        if played { return "Watched" }
        if pos > 0 { return "In progress" }
        return ""
    }

    private func episodeTitle(_ ep: JellyfinClient.LibraryItem) -> String {
        if let i = ep.indexNumber {
            return "\(i). \(ep.name ?? "Episode")"
        }
        return ep.name ?? "Episode"
    }
}

/// A slim, premium progress bar (no hard-coded colors; uses your theme tokens).
private struct EpisodeProgressBar: View {
    let progress: Double   // 0...1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(height: 4)

                Capsule()
                    .fill(BrockbusterTheme.ticketYellow.opacity(0.95))
                    .frame(width: max(4, w * progress), height: 4)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}


private enum PosterKind {
    case poster
    case thumb
}

/// Convenience wrapper to pull the right image kind for posters/thumbnails.
private struct PosterImage: View {
    @EnvironmentObject private var session: SessionStore
    let item: JellyfinClient.LibraryItem
    let kind: PosterKind
    var fallbackItem: JellyfinClient.LibraryItem? = nil

    var body: some View {
        Group {
            if let url = imageURL() {
                BBCachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.08))
            Image(systemName: "photo")
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func imageURL() -> URL? {
        switch kind {
        case .poster:
            return session.itemImageURL(for: item, maxWidth: 720)
        case .thumb:
            // Episodes usually have a Primary image (frame thumbnail). If not, fall back to the series poster when provided.
            if let url = session.itemImageURL(for: item, maxWidth: 420) {
                return url
            }
            if let fallback = fallbackItem, let url = session.itemImageURL(for: fallback, maxWidth: 420) {
                return url
            }
            return nil
        }
    }
}
