import SwiftUI

/// Traditional TV series view:
/// - Header with show artwork + metadata
/// - Season selector
/// - Episode list for selected season (with optional episode search)
struct SeriesDetailView: View {
    @EnvironmentObject private var session: SessionStore
    let series: JellyfinClient.LibraryItem

    @State private var details: JellyfinClient.LibraryItem?
    @State private var seasons: [JellyfinClient.LibraryItem] = []
    @State private var selectedSeason: JellyfinClient.LibraryItem?
    @State private var episodes: [JellyfinClient.LibraryItem] = []

    @State private var isLoading = true
    @State private var isLoadingEpisodes = false
    @State private var errorMessage: String?

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
        .navigationTitle(series.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - UI

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                PosterImage(item: details ?? series, kind: .poster)
                    .frame(width: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text(details?.name ?? series.name)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(BrockbusterTheme.textPrimary)

                    HStack(spacing: 8) {
                        if let year = (details?.productionYear ?? series.productionYear) {
                            Text(String(year))
                        }
                        if let rating = details?.officialRating, !rating.isEmpty {
                            Text(rating)
                        }
                        if let runTime = details?.runTimeTicks {
                            Text(BrockbusterFormat.runtimeMinutes(fromTicks: runTime))
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
                            BrockbusterTheme.Pill(text: seasonDisplayName(season))
                        }
                        if isLoading {
                            BrockbusterTheme.Pill(text: "Loading…", icon: "sparkles")
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
                    ForEach(seasons) { season in
                        let isSelected = season.id == selectedSeason?.id
                        Button {
                            Task { await selectSeason(season) }
                        } label: {
                            Text(seasonDisplayName(season))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSelected ? .black : BrockbusterTheme.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Group {
                                        if isSelected {
                                            BrockbusterTheme.ticketYellow
                                        } else {
                                            .white.opacity(0.10)
                                        }
                                    }
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(.white.opacity(isSelected ? 0 : 0.12), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
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
                            EpisodeRow(episode: ep)
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
}

private struct EpisodeRow: View {
    let episode: JellyfinClient.LibraryItem

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                PosterImage(item: episode, kind: .thumb)
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
            return session.itemImageURL(id: item.id, imageType: "Primary", maxWidth: 720)
        case .thumb:
            // Episodes usually have a Primary. If not, fall back to series poster.
            // Episodes often have a Primary image representing the frame thumbnail.
            // Fall back to the series poster if none is available.
            if let url = session.itemImageURL(id: item.id, imageType: "Primary", maxWidth: 420) {
                return url
            }
            if let seriesId = item.seriesId ?? item.parentId {
                return session.itemImageURL(id: seriesId, imageType: "Primary", maxWidth: 720)
            }
            return nil
        }
    }
}
