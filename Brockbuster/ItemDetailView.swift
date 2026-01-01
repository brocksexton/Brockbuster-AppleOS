import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Displays detailed information about a single media item.
/// - Episodes: shows watch state + progress, season/episode numbers, air date (when available),
///   and technical playback specs (resolution/codecs/subtitles) sourced from PlaybackInfo.
/// - Movies: poster-forward presentation and technical specs.
struct ItemDetailView: View {
    let item: JellyfinClient.LibraryItem

    @EnvironmentObject private var session: SessionStore
    @Environment(\.colorScheme) private var colorScheme

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var detail: JellyfinClient.ItemDetail?
    @State private var playbackInfo: JellyfinClient.PlaybackInfo?
    @State private var people: [JellyfinClient.Person] = []

    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var playbackSubtitle: String = ""
    @State private var playerSheet: PresentedPlayerURL?

    @State private var isTogglingFavorite: Bool = false
    @State private var favoriteOverride: Bool? = nil

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroSection

                    contentSection
                        .padding(.horizontal, 16)
                        // Keep the play button and cards visually connected to the hero.
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: bottomContentInset)
            }
        }
        .navigationTitle(detail?.name ?? item.name)
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
        .task { await loadAll() }
        .sheet(item: $playerSheet, onDismiss: {
            Task { await loadAll() }
        }) { sheet in
            PlayerView(
                itemId: item.id,
                url: sheet.context.url,
                title: detail?.name ?? item.name,
                subtitle: playbackSubtitle,
                posterURL: session.itemImageURL(for: item, maxWidth: 700),
                playbackContext: sheet.context,
                startPositionTicks: sheet.startPositionTicks
            )
        }
    }

    // MARK: - UI Sections
    private var heroSection: some View {
        GeometryReader { geo in
            let size = geo.size
            let height = heroHeight(for: size)

            ZStack(alignment: .bottomLeading) {
                heroBackdrop
                    .frame(width: size.width, height: height)
                    .clipped()

                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.84)]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                heroContent
                    .frame(maxWidth: heroContentMaxWidth(for: size), alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .frame(width: size.width, height: height)
            .clipped()
        }
        // IMPORTANT: The outer frame must match the computed hero height, otherwise
        // rotations (and iPad/tvOS wide layouts) can leave unused space below the hero.
        .frame(height: heroHeightStatic)
    }

    private var heroBackdrop: some View {
        Group {
            if let url = heroImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(.black.opacity(0.18))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle().fill(.black.opacity(0.18))
                            .overlay(Image(systemName: "film.fill").foregroundStyle(BrockbusterTheme.ticketYellow))
                    @unknown default:
                        Rectangle().fill(.black.opacity(0.18))
                    }
                }
            } else {
                Rectangle().fill(.black.opacity(0.18))
                    .overlay(Image(systemName: "film.fill").foregroundStyle(BrockbusterTheme.ticketYellow))
            }
        }
    }

    private var heroContent: some View {
        Group {
            if isWideLayout {
                HStack(alignment: .bottom, spacing: 16) {
                    artworkCard
                        .frame(width: isMovie ? 140 : 160, height: isMovie ? 210 : 100)

                    VStack(alignment: .leading, spacing: 10) {
                        heroTitleBlock
                        heroChips
                    }
                    .frame(maxWidth: 720, alignment: .leading)

                    Spacer(minLength: 0)
                }
            } else {
                HStack(alignment: .bottom, spacing: 14) {
                    artworkCard

                    VStack(alignment: .leading, spacing: 8) {
                        heroTitleBlock
                        heroChips
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var heroTitleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail?.name ?? item.name)
                .font(.system(size: isWideLayout ? 34 : 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(isWideLayout ? 2 : 2)
                .minimumScaleFactor(0.80)

            if let sub = subtitleLine, !sub.isEmpty {
                Text(sub)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
        }
    }

    private var heroChips: some View {
        Group {
            if heroBadges.isEmpty {
                EmptyView()
            } else if isWideLayout {
                AdaptiveChipsGrid(chips: heroBadges)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(heroBadges, id: \.self) { chip in
                            SpecChip(text: chip)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var contentSection: some View {
        Group {
            if isLoading && detail == nil {
                VStack(spacing: 16) {
                    ProgressView("Loading…")
                        .progressViewStyle(CircularProgressViewStyle(tint: BrockbusterTheme.ticketYellow))
                    Text("Fetching details…")
                        .foregroundStyle(BrockbusterTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 380)
            } else if let errorMessage {
                GlassCard {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            } else if detail != nil {
                VStack(alignment: .leading, spacing: 16) {
                    actionRow

                    if shouldShowWatchStatus {
                        WatchStatusCard(
                            title: watchTitle,
                            icon: watchIcon,
                            iconColor: watchIconColor,
                            progress: watchProgressFraction,
                            elapsedText: watchElapsedText,
                            totalText: watchTotalText,
                            percentText: watchPercentText,
                            lastPlayedText: watchLastPlayedText
                        )
                    }

                    if let overview = detail?.overview, !overview.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview")
                                    .font(.headline)
                                    .foregroundStyle(BrockbusterTheme.textPrimary)
                                Text(overview)
                                    .font(.subheadline)
                                    .foregroundStyle(BrockbusterTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    detailsCard

                    if let source = playbackInfo?.mediaSources.first {
                        technicalSpecsCard(source: source)
                    }

                    castCard
                }
                .padding(.top, 12)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var artworkCard: some View {
        let url = artworkPosterURL

        if isMovie {
            PosterImageURLView(url: url)
                .frame(width: 92, height: 138)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 10)
        } else if isEpisode {
            PosterImageFallbackView(urls: episodeCoverArtFallbackURLs)
                .frame(width: 92, height: 138)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 10)
        } else {
            PosterImageURLView(url: url)
                .frame(width: 110, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 10)
        }
    }

    /// Poster-style artwork shown in the hero overlay.
    ///
    /// - Movies: `Primary` poster.
    /// - Episodes: prefer episode `Thumb`, then episode `Primary`, then Season `Primary`, then Series `Primary`.
    /// - Other: prefer `Thumb`, fall back to `Primary`.
    private var artworkPosterURL: URL? {
        if isMovie {
            return session.itemImageURL(for: item, kind: "Primary", maxWidth: 720)
        }

        if isEpisode {
            // The artworkCard for episodes uses PosterImageFallbackView with a richer fallback chain.
            // This value is kept as a conservative single-URL fallback.
            return (item.seasonId.flatMap { session.itemImageURL(itemId: $0, kind: "Primary", maxWidth: 720) })
                ?? (item.seriesId.flatMap { session.itemImageURL(itemId: $0, kind: "Primary", maxWidth: 720) })
                ?? session.itemImageURL(for: item, kind: "Primary", maxWidth: 720)
                ?? session.itemImageURL(for: item, kind: "Thumb", maxWidth: 720)
        }

        return session.itemImageURL(for: item, kind: "Thumb", maxWidth: 720)
            ?? session.itemImageURL(for: item, kind: "Primary", maxWidth: 720)
    }

    
    /// Fallback chain for Episode "cover art" (the small poster tile).
    /// Preference:
    /// 1) Season Primary, then Season Thumb
    /// 2) Series Primary, then Series Thumb
    /// 3) Episode Primary (still) as a last resort
    ///
    /// NOTE: Jellyfin image URLs may be non-nil even when the server has no artwork (404),
    /// so the UI must attempt these URLs in-order and advance on failure.
    private var episodeCoverArtFallbackURLs: [URL] {
        var urls: [URL] = []

        if let seasonId = item.seasonId {
            if let u = session.itemImageURL(itemId: seasonId, kind: "Primary", maxWidth: 720) { urls.append(u) }
            if let u = session.itemImageURL(itemId: seasonId, kind: "Thumb",   maxWidth: 720) { urls.append(u) }
        }

        if let seriesId = item.seriesId {
            if let u = session.itemImageURL(itemId: seriesId, kind: "Primary", maxWidth: 720) { urls.append(u) }
            if let u = session.itemImageURL(itemId: seriesId, kind: "Thumb",   maxWidth: 720) { urls.append(u) }
        }

        if let u = session.itemImageURL(for: item, kind: "Primary", maxWidth: 720) { urls.append(u) }

        // De-dupe while preserving order.
        var seen = Set<String>()
        var unique: [URL] = []
        for u in urls {
            let key = u.absoluteString
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(u)
            }
        }
        return unique
    }


private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: playItem) {
                HStack(spacing: 10) {
                    Image(systemName: watchState == .inProgress ? "play.fill" : "play.circle.fill")
                        .font(.headline.weight(.bold))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(playButtonTitle)
                            .font(.subheadline.weight(.semibold))
                        if let hint = playbackHintLine, !hint.isEmpty {
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(.black.opacity(0.70))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.black)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(BrockbusterTheme.ticketYellow)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                Task { await toggleFavorite() }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)

                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isFavorite ? BrockbusterTheme.ticketYellow : BrockbusterTheme.textPrimary)
                        .padding(12)
                }
                .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .disabled(isTogglingFavorite || detail == nil || session.currentUser == nil)
        }
    }

    private var detailsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Details")
                    .font(.headline)
                    .foregroundStyle(BrockbusterTheme.textPrimary)

                let pairs = metadataPairs
                if pairs.isEmpty {
                    Text("No additional metadata available.")
                        .font(.caption)
                        .foregroundStyle(BrockbusterTheme.textSecondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(pairs, id: \.key) { kv in
                            MetaPair(title: kv.key, value: kv.value)
                        }
                    }
                }
            }
        }
    }

    private func technicalSpecsCard(source: JellyfinClient.PlaybackMediaSource) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Technical Specs")
                    .font(.headline)
                    .foregroundStyle(BrockbusterTheme.textPrimary)

                let chips = technicalChips(from: source)
                if chips.isEmpty {
                    Text("No stream information available for this item.")
                        .font(.caption)
                        .foregroundStyle(BrockbusterTheme.textSecondary)
                } else {
                    AdaptiveChipsGrid(chips: chips)
                }
            }
        }
    }

    private var castCard: some View {
        let cast = people.filter { ($0.type ?? "").lowercased().contains("actor") || ($0.role ?? "").isEmpty == false }
        return Group {
            if !cast.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cast")
                            .font(.headline)
                            .foregroundStyle(BrockbusterTheme.textPrimary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(cast.prefix(24)) { person in
                                    VStack(spacing: 8) {
                                        PersonAvatar(url: session.personImageURL(for: person, maxWidth: 240))
                                            .frame(width: 64, height: 64)

                                        Text(person.name)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(BrockbusterTheme.textPrimary)
                                            .lineLimit(1)

                                        if let role = person.role, !role.isEmpty {
                                            Text(role)
                                                .font(.caption2)
                                                .foregroundStyle(BrockbusterTheme.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(width: 92)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func loadAll() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        favoriteOverride = nil

        do {
            async let d = session.fetchItemDetails(itemId: item.id)
            async let p = session.fetchPeople(for: item.id)
            async let pb = session.fetchPlaybackInfo(itemId: item.id)

            detail = try await d

            do { people = try await p } catch { people = [] }
            do { playbackInfo = try await pb } catch { playbackInfo = nil }

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Favorites

    @MainActor
    private func toggleFavorite() async {
        guard detail != nil else { return }
        guard session.currentUser != nil else { return }

        let newValue = !isFavorite
        isTogglingFavorite = true
        favoriteOverride = newValue

        do {
            try await session.setFavorite(itemId: item.id, isFavorite: newValue)
            favoriteOverride = nil
            await loadAll()
        } catch {
            favoriteOverride = nil
            errorMessage = error.localizedDescription
        }

        isTogglingFavorite = false
    }

    // MARK: - Playback

    private func playItem() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            do {
                let context = try await session.playbackContext(for: item.id)
                await MainActor.run {
                    playbackSubtitle = buildPlaybackSubtitle()
                    playerSheet = PresentedPlayerURL(itemId: item.id, context: context, startPositionTicks: resolvedUserData?.playbackPositionTicks ?? 0)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func buildPlaybackSubtitle() -> String {
        var parts: [String] = []

        if isEpisode {
            if let s = item.parentIndexNumber, s > 0 { parts.append("S\(s)") }
            if let e = item.indexNumber, e > 0 { parts.append("E\(e)") }
        } else if let year = detail?.productionYear {
            parts.append(String(year))
        }

        if let ticks = (detail?.runTimeTicks ?? item.runtimeTicks) {
            parts.append(formatRuntime(ticks))
        }
        if let rating = detail?.communityRating {
            parts.append(String(format: "%.1f★", rating))
        }
        return parts.joined(separator: " • ")
    }

    // MARK: - Derived presentation

    private var background: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    gradient: Gradient(colors: [
                        BrockbusterTheme.brockDark.opacity(0.90),
                        BrockbusterTheme.brockBlue.opacity(0.80)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        BrockbusterTheme.brockBlue.opacity(0.10),
                        BrockbusterTheme.brockGold.opacity(0.08)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }



    private var isWideLayout: Bool {
        #if os(tvOS)
        return true
        #else
        // Treat iPhone landscape as “wide” so the hero composition stays intentional.
        if horizontalSizeClass == .regular { return true }
        if horizontalSizeClass == .compact, verticalSizeClass == .compact { return true }
        return false
        #endif
    }

    private func heroHeight(for size: CGSize) -> CGFloat {
        // 16:9-ish hero with clamps for consistency across iPhone/iPad/tvOS
        let proposed = size.width * 0.56
        return min(max(proposed, 260), 520)
    }

    private var heroHeightStatic: CGFloat {
        // The outer frame must match the heroHeight(for:) calculation so layout does not
        // reserve extra vertical space (especially noticeable on rotation).
        #if canImport(UIKit)
        return heroHeight(for: UIScreen.main.bounds.size)
        #else
        return 360
        #endif
    }

    private func heroContentMaxWidth(for size: CGSize) -> CGFloat {
        if isWideLayout {
            // Prevent the overlay content from stretching too far on iPad/tvOS.
            return min(size.width - 32, 980)
        }
        return size.width - 32
    }

    private var heroImageURL: URL? {
        // Episodes frequently lack Backdrop art. Fall back to Season/Series artwork.
        // (Backdrop preferred for hero; Primary as a final fallback.)
        if let url = session.itemImageURL(for: item, kind: "Backdrop", maxWidth: 1600) {
            return url
        }

        if isEpisode {
            if let seasonId = item.seasonId {
                if let url = session.itemImageURL(itemId: seasonId, kind: "Backdrop", maxWidth: 1600) {
                    return url
                }
            }
            if let seriesId = item.seriesId {
                if let url = session.itemImageURL(itemId: seriesId, kind: "Backdrop", maxWidth: 1600) {
                    return url
                }
            }
            // Some servers only have Primary art for Season/Series.
            if let seasonId = item.seasonId {
                if let url = session.itemImageURL(itemId: seasonId, kind: "Primary", maxWidth: 1200) {
                    return url
                }
            }
            if let seriesId = item.seriesId {
                if let url = session.itemImageURL(itemId: seriesId, kind: "Primary", maxWidth: 1200) {
                    return url
                }
            }
        }

        return session.itemImageURL(for: item, maxWidth: 1200)
    }

    private var isEpisode: Bool {
        (item.type ?? "").lowercased() == "episode"
    }

    private var isMovie: Bool {
        (item.type ?? "").lowercased() == "movie"
    }

    private var subtitleLine: String? {
        if isEpisode {
            var bits: [String] = []
            if let s = item.parentIndexNumber, s > 0, let e = item.indexNumber, e > 0 {
                bits.append("S\(s)E\(e)")
            }
            if let aired = formattedPremiereDate {
                bits.append("Aired \(aired)")
            }
            return bits.isEmpty ? nil : bits.joined(separator: " • ")
        } else {
            var bits: [String] = []
            if let year = detail?.productionYear { bits.append(String(year)) }
            if let genres = detail?.genres, let first = genres.first { bits.append(first) }
            if let ticks = detail?.runTimeTicks ?? item.runtimeTicks { bits.append(formatRuntime(ticks)) }
            return bits.isEmpty ? nil : bits.joined(separator: " • ")
        }
    }

    private var heroBadges: [String] {
        var out: [String] = []
        if let rating = detail?.communityRating { out.append(String(format: "%.1f★", rating)) }
        if let ticks = detail?.runTimeTicks ?? item.runtimeTicks { out.append(formatRuntime(ticks)) }
        if let source = playbackInfo?.mediaSources.first {
            out.append(contentsOf: heroTechBadges(from: source))
        }
        return Array(out.prefix(6))
    }

    private func heroTechBadges(from source: JellyfinClient.PlaybackMediaSource) -> [String] {
        var out: [String] = []
        let streams = source.mediaStreams ?? []
        let video = streams.first { ($0.type ?? "").lowercased() == "video" }
        let audio = streams.first { ($0.type ?? "").lowercased() == "audio" && ($0.isDefault ?? false) } ??
                    streams.first { ($0.type ?? "").lowercased() == "audio" }

        if let v = video, let w = v.width, let h = v.height {
            out.append(classifyResolution(width: w, height: h))
            if let range = v.videoRange, !range.isEmpty, range.lowercased() != "sdr" {
                out.append(range.uppercased())
            }
        }
        if let v = video, let codec = v.codec { out.append(codec.uppercased()) }
        if let a = audio, let codec = a.codec { out.append(codec.uppercased()) }
        return out
    }

    private var metadataPairs: [(key: String, value: String)] {
        var pairs: [(String, String)] = []

        if isEpisode {
            if let s = item.parentIndexNumber, s > 0 { pairs.append(("Season", "\(s)")) }
            if let e = item.indexNumber, e > 0 { pairs.append(("Episode", "\(e)")) }
            if let aired = formattedPremiereDate { pairs.append(("Release Date", aired)) }
        }

        if let year = detail?.productionYear { pairs.append(("Year", "\(year)")) }
        if let ticks = detail?.runTimeTicks ?? item.runtimeTicks { pairs.append(("Runtime", formatRuntime(ticks))) }
        if let rating = detail?.communityRating { pairs.append(("Rating", String(format: "%.1f", rating))) }

        if let genres = detail?.genres, !genres.isEmpty {
            pairs.append(("Genres", genres.prefix(4).joined(separator: ", ")))
        }

        if let source = playbackInfo?.mediaSources.first {
            if let container = source.container, !container.isEmpty { pairs.append(("Container", container.uppercased())) }
            if let br = source.bitrate, br > 0 { pairs.append(("Bitrate", formatBitrate(br))) }
        }

        return pairs
    }

    private var formattedPremiereDate: String? {
        let iso = detail?.premiereDate ?? item.premiereDate
        guard let iso, !iso.isEmpty else { return nil }
        return formatISODate(iso)
    }

    
    /// Extra bottom inset so content never sits under the custom floating tab bar on iPhone.
    /// (The system safe-area does not account for our custom overlay.)
    private var bottomContentInset: CGFloat {
        #if os(iOS)
        // In landscape the floating tab bar consumes less vertical space.
        if horizontalSizeClass == .compact, verticalSizeClass == .compact {
            return 96
        }
        return 120
        #else
        return 44
        #endif
    }

private func technicalChips(from source: JellyfinClient.PlaybackMediaSource) -> [String] {
        var out: [String] = []
        let streams = source.mediaStreams ?? []
        let videoStreams = streams.filter { ($0.type ?? "").lowercased() == "video" }
        let audioStreams = streams.filter { ($0.type ?? "").lowercased() == "audio" }
        let subStreams = streams.filter { ($0.type ?? "").lowercased() == "subtitle" }

        if let v = videoStreams.first {
            if let w = v.width, let h = v.height { out.append("\(w)x\(h) • \(classifyResolution(width: w, height: h))") }
            if let codec = v.codec { out.append("Video • \(codec.uppercased())") }
            if let range = v.videoRange, !range.isEmpty, range.lowercased() != "sdr" { out.append(range.uppercased()) }
            if let br = v.bitRate, br > 0 { out.append("Video BR • \(formatBitrate(br))") }
        }

        if let a = audioStreams.first(where: { $0.isDefault == true }) ?? audioStreams.first {
            var aLine: [String] = []
            if let codec = a.codec { aLine.append(codec.uppercased()) }
            if let ch = a.channels { aLine.append("\(ch)ch") }
            if let layout = a.channelLayout, !layout.isEmpty { aLine.append(layout.uppercased()) }
            if !aLine.isEmpty { out.append("Audio • " + aLine.joined(separator: " • ")) }
        }

        if !subStreams.isEmpty {
            let langs = subStreams.compactMap { $0.language }.prefix(4)
            if langs.isEmpty {
                out.append("Subtitles • \(subStreams.count)")
            } else {
                out.append("Subtitles • " + langs.joined(separator: ", ").uppercased())
            }
        }

        if let container = source.container, !container.isEmpty { out.append("Container • \(container.uppercased())") }
        if let size = source.size, size > 0 { out.append("Size • \(formatBytes(size))") }

        return out
    }

    // MARK: - Watch status

    private enum WatchState { case notStarted, inProgress, watched }

    private var resolvedUserData: JellyfinClient.UserData? { detail?.userData ?? item.userData }

    private var isFavorite: Bool {
        if let override = favoriteOverride { return override }
        return resolvedUserData?.isFavorite ?? false
    }

    private var shouldShowWatchStatus: Bool {
        resolvedUserData?.played != nil || (resolvedUserData?.playbackPositionTicks ?? 0) > 0
    }

    private var watchState: WatchState {
        if resolvedUserData?.played == true { return .watched }
        if (resolvedUserData?.playbackPositionTicks ?? 0) > 0 { return .inProgress }
        return .notStarted
    }

    private var playButtonTitle: String {
        switch watchState {
        case .watched: return "Play Again"
        case .inProgress: return "Resume"
        case .notStarted: return "Play"
        }
    }

    private var playbackHintLine: String? {
        switch watchState {
        case .watched:
            return "Watched"
        case .inProgress:
            if let e = watchElapsedText, let t = watchTotalText { return "\(e) / \(t)" }
            return "In progress"
        case .notStarted:
            return nil
        }
    }

    private var watchTotalTicks: Int? { detail?.runTimeTicks ?? item.runtimeTicks }

    private var watchProgressFraction: Double? {
        switch watchState {
        case .watched:
            return 1.0
        case .inProgress:
            let pos = Double(resolvedUserData?.playbackPositionTicks ?? 0)
            guard pos > 0 else { return nil }
            let total = Double(watchTotalTicks ?? 0)
            guard total > 0 else { return nil }
            return max(0.0, min(pos / total, 0.995))
        case .notStarted:
            return nil
        }
    }

    private var watchElapsedText: String? {
        let pos = resolvedUserData?.playbackPositionTicks ?? 0
        guard pos > 0 else { return nil }
        return formatClockTime(pos)
    }

    private var watchTotalText: String? {
        guard let total = watchTotalTicks, total > 0 else { return nil }
        return formatClockTime(total)
    }

    private var watchPercentText: String? {
        guard let frac = watchProgressFraction else { return nil }
        return "\(Int(frac * 100.0))%"
    }

    private var watchLastPlayedText: String? {
        guard let iso = resolvedUserData?.lastPlayedDate else { return nil }
        if let dt = ISO8601DateFormatter().date(from: iso) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: dt)
        }
        return iso
    }

    private var watchTitle: String {
        switch watchState {
        case .watched: return "Watched"
        case .inProgress: return "In Progress"
        case .notStarted: return "Not Started"
        }
    }

    private var watchIcon: String {
        switch watchState {
        case .watched: return "checkmark.circle.fill"
        case .inProgress: return "clock.fill"
        case .notStarted: return "circle"
        }
    }

    private var watchIconColor: Color {
        switch watchState {
        case .watched: return BrockbusterTheme.ticketYellow
        case .inProgress: return .white.opacity(0.80)
        case .notStarted: return .white.opacity(0.55)
        }
    }

    // MARK: - Formatting

    private func classifyResolution(width: Int, height: Int) -> String {
        let maxDim = max(width, height)
        if maxDim >= 3800 { return "4K" }
        if maxDim >= 2500 { return "1440p" }
        if maxDim >= 1900 { return "1080p" }
        if maxDim >= 1200 { return "720p" }
        return "\(height)p"
    }

    private func formatRuntime(_ ticks: Int) -> String {
        let seconds = Double(ticks) / 10_000_000.0
        let minutes = Int(seconds) / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return hours > 0 ? "\(hours)h \(remainingMinutes)m" : "\(remainingMinutes)m"
    }

    private func formatClockTime(_ ticks: Int) -> String {
        let totalSeconds = Int(Double(ticks) / 10_000_000.0)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return "\(h):" + String(format: "%02d:%02d", m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatBitrate(_ bps: Int) -> String {
        let mbps = Double(bps) / 1_000_000.0
        if mbps >= 1 { return String(format: "%.1f Mbps", mbps) }
        let kbps = Double(bps) / 1_000.0
        return String(format: "%.0f Kbps", kbps)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private func formatISODate(_ iso: String) -> String? {
        if let dt = ISO8601DateFormatter().date(from: iso) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: dt)
        }
        return nil
    }
}

// MARK: - Supporting Views

private struct PresentedPlayerURL: Identifiable {
    let itemId: String
    let context: SessionStore.PlaybackContext
    let startPositionTicks: Int
    var id: String { itemId }
}

private struct PosterImageURLView: View {
    let url: URL?
    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.08))
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.08))
                            .overlay(Image(systemName: "film").foregroundStyle(.white.opacity(0.6)))
                    @unknown default:
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.08))
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.08))
                    .overlay(Image(systemName: "film").foregroundStyle(.white.opacity(0.6)))
            }
        }
        .clipped()
    }

}

private struct PosterImageFallbackView: View {
    let urls: [URL]

    @State private var index: Int = 0

    var body: some View {
        Group {
            if let url = urls[safe: index] {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        placeholder
                            .onAppear {
                                if index + 1 < urls.count {
                                    index += 1
                                }
                            }
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
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.white.opacity(0.08))
            .overlay(Image(systemName: "film").foregroundStyle(.white.opacity(0.6)))
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        guard idx >= 0, idx < count else { return nil }
        return self[idx]
    }
}


private struct PersonAvatar: View {
    let url: URL?
    var body: some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle().fill(.white.opacity(0.10))
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Circle().fill(.white.opacity(0.10))
                            .overlay(Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.6)))
                    @unknown default:
                        Circle().fill(.white.opacity(0.10))
                    }
                }
            } else {
                Circle().fill(.white.opacity(0.10))
                    .overlay(Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.6)))
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
        .clipped()
    }
}

private struct MetaPair: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.60))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpecChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

private struct AdaptiveChipsGrid: View {
    let chips: [String]
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(chips, id: \.self) { chip in
                SpecChip(text: chip)
            }
        }
    }
}

private struct WatchStatusCard: View {
    let title: String
    let icon: String
    let iconColor: Color
    let progress: Double?
    let elapsedText: String?
    let totalText: String?
    let percentText: String?
    let lastPlayedText: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(iconColor)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrockbusterTheme.textPrimary)

                    Spacer(minLength: 0)

                    if title == "In Progress", let pct = percentText {
                        Text(pct)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrockbusterTheme.textSecondary)
                    }
                }

                if let progress, title == "In Progress" || title == "Watched" {
                    EpisodeProgressBar(progress: progress)
                }

                if title == "In Progress", let e = elapsedText, let t = totalText {
                    Text("\(e) / \(t)")
                        .font(.caption)
                        .foregroundStyle(BrockbusterTheme.textSecondary)
                }

                if title == "Watched", let lastPlayedText {
                    Text("Last played: \(lastPlayedText)")
                        .font(.caption)
                        .foregroundStyle(BrockbusterTheme.textSecondary)
                }
            }
        }
    }
}

private struct EpisodeProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14)).frame(height: 4)
                Capsule()
                    .fill(BrockbusterTheme.ticketYellow.opacity(0.95))
                    .frame(width: max(4, w * max(0, min(progress, 1))), height: 4)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
