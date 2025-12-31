import SwiftUI

/// Traditional TV series view:
/// - Header with show artwork + metadata
/// - Season selector
/// - Episode list for selected season (with optional episode search)
struct SeriesDetailView: View {
    @EnvironmentObject private var session: SessionStore
    let series: JellyfinClient.LibraryItem

    @State private var details: JellyfinClient.ItemDetail?
    @State private var seasons: [JellyfinClient.LibraryItem] = []
    @State private var selectedSeason: JellyfinClient.LibraryItem?
    @State private var episodes: [JellyfinClient.LibraryItem] = []

    @State private var isLoading = true
    @State private var isLoadingEpisodes = false
    @State private var errorMessage: String?
    
    @State private var showPlayer = false
    @State private var playerURL: URL?

    @State private var episodeQuery = ""

    private var filteredEpisodes: [JellyfinClient.LibraryItem] {
        let q = episodeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return episodes }
        return episodes.filter { ($0.name).localizedCaseInsensitiveContains(q) }
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
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showPlayer) {
            if let url = playerURL {
                PlayerView(
                    url: url,
                    title: details?.name ?? series.name ?? "",
                    posterURL: session.itemImageURL(for: series, maxWidth: 700)
                )
            }
        }
    }

    // MARK: - UI

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
                        SeasonPill(
                            title: seasonDisplayName(season),
                            isSelected: isSelected,
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
                TextField("Search episodes", text: $episodeQuery)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
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

            if selectedSeason == nil {
                selectedSeason = seasons.first
            }

            if let selectedSeason {
                await selectSeason(selectedSeason)
            }
        } catch {
            errorMessage = "Unable to load show details. \(error.localizedDescription)"
        }

        isLoading = false
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
        } catch {
            episodes = []
            errorMessage = "Unable to load episodes. \(error.localizedDescription)"
        }
    }

    private func seasonDisplayName(_ season: JellyfinClient.LibraryItem) -> String {
        if let index = season.indexNumber {
            return index == 0 ? "Specials" : "Season \(index)"
        }
        return season.name
    }
    
    private func play(episode: JellyfinClient.LibraryItem) async {
        guard !isLoadingEpisodes else { return }
        do {
            let url = try await session.streamURL(for: episode.id)
            playerURL = url
            showPlayer = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SeasonPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .black : BrockbusterTheme.textPrimary)
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
            HStack(spacing: 12) {
                PosterImage(item: episode, kind: .thumb, fallbackItem: seriesFallback)
                    .frame(width: 110, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )

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

    private func episodeTitle(_ ep: JellyfinClient.LibraryItem) -> String {
        if let i = ep.indexNumber {
            return "\(i). \(ep.name ?? "Episode")"
        }
        return ep.name
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
                AsyncImage(url: url) { phase in
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
            Image(systemName: kind == .poster ? "tv" : "film")
                .font(.title3)
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

