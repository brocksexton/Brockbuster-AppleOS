import SwiftUI

/// Displays detailed information about a single media item. The view fetches
/// additional metadata from the server when it appears and shows a large
/// hero image, title, runtime, year, overview, cast, and playback controls.
/// For episodes (and any items with UserData), it also shows watch state:
/// - Watched (✓) + last played
/// - In progress (progress bar + elapsed/total + percent)
/// - Not started
struct ItemDetailView: View {
    /// The basic library item used to identify the item to fetch. Contains
    /// minimal information such as id and name, and may already include UserData.
    let item: JellyfinClient.LibraryItem

    @EnvironmentObject private var session: SessionStore
    @State private var detail: JellyfinClient.ItemDetail?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var people: [JellyfinClient.Person] = []
    @State private var playbackSubtitle: String = ""
    @State private var playerSheet: PresentedPlayerURL?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Background (make light mode cleaner)
            Group {
                if colorScheme == .dark {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            BrockbusterTheme.brockDark.opacity(0.82),
                            BrockbusterTheme.brockBlue.opacity(0.82)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    LinearGradient(
                        gradient: Gradient(colors: lightModeGradientColors),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    if let detail = detail {
                        // HERO (edge-to-edge)
                        ZStack {
                            if let url = session.itemImageURL(for: detail, maxWidth: 1200) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        Rectangle().fill(.black.opacity(0.18))
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    case .failure:
                                        Rectangle()
                                            .fill(.black.opacity(0.18))
                                            .overlay(Image(systemName: "film.fill").foregroundColor(BrockbusterTheme.brockGold))
                                    @unknown default:
                                        Rectangle().fill(.black.opacity(0.18))
                                    }
                                }
                            } else {
                                Rectangle()
                                    .fill(.black.opacity(0.18))
                                    .overlay(Image(systemName: "film.fill").foregroundColor(BrockbusterTheme.brockGold))
                            }

                            LinearGradient(
                                gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.65)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipped()

                        // CONTENT (padded)
                        VStack(alignment: .leading, spacing: 18) {
                            Text(detail.name)
                                .font(BrockbusterTheme.Fonts.largeTitle)
                                .foregroundColor(colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)

                            if let tagline = detail.taglines?.first, !tagline.isEmpty {
                                Text(tagline)
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor((colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark).opacity(0.85))
                            }

                            // Info chips (year, runtime, rating)
                            HStack(spacing: 12) {
                                if let year = detail.productionYear {
                                    InfoChip(text: String(year))
                                }
                                if let runtime = detail.runTimeTicks {
                                    InfoChip(text: formatRuntime(runtime))
                                }
                                if let rating = detail.communityRating {
                                    InfoChip(text: String(format: "%.1f ★", rating))
                                }
                            }

                            // Watch status / progress (episodes & any items with UserData)
                            if shouldShowWatchStatus {
                                WatchStatusCard(
                                    state: watchState,
                                    progressFraction: watchProgressFraction,
                                    elapsedText: watchElapsedText,
                                    totalText: watchTotalText,
                                    percentText: watchPercentText,
                                    lastPlayedText: watchLastPlayedText
                                )
                            }

                            // Genres
                            if let genres = detail.genres, !genres.isEmpty {
                                Text(genres.joined(separator: ", "))
                                    .font(BrockbusterTheme.Fonts.body)
                                    .foregroundColor((colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark).opacity(0.75))
                            }

                            // Overview
                            if let overview = detail.overview {
                                Text(overview)
                                    .font(BrockbusterTheme.Fonts.body)
                                    .foregroundColor((colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark).opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            // Cast
                            let cast = people.filter { ($0.type ?? "").lowercased().contains("actor") || ($0.role ?? "").isEmpty == false }
                            if !cast.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Cast")
                                        .font(.headline)
                                        .foregroundColor(colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 14) {
                                            ForEach(cast.prefix(24)) { person in
                                                VStack(spacing: 8) {
                                                    ZStack {
                                                        if let url = session.personImageURL(for: person, maxWidth: 240) {
                                                            AsyncImage(url: url) { phase in
                                                                switch phase {
                                                                case .empty:
                                                                    Circle().fill(BrockbusterTheme.brockDark.opacity(0.35))
                                                                case .success(let image):
                                                                    image.resizable().scaledToFill()
                                                                case .failure:
                                                                    Circle().fill(BrockbusterTheme.brockDark.opacity(0.35))
                                                                        .overlay(Image(systemName: "person.fill").foregroundColor(BrockbusterTheme.brockGold))
                                                                @unknown default:
                                                                    EmptyView()
                                                                }
                                                            }
                                                        } else {
                                                            Circle().fill(BrockbusterTheme.brockDark.opacity(0.35))
                                                                .overlay(Image(systemName: "person.fill").foregroundColor(BrockbusterTheme.brockGold))
                                                        }
                                                    }
                                                    .frame(width: 64, height: 64)
                                                    .clipShape(Circle())
                                                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))

                                                    Text(person.name)
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundColor(colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)
                                                        .lineLimit(1)

                                                    if let role = person.role, !role.isEmpty {
                                                        Text(role)
                                                            .font(.caption2)
                                                            .foregroundColor((colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark).opacity(0.70))
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

                            // Play button
                            Button(action: playItem) {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                    Text(playButtonTitle)
                                        .font(BrockbusterTheme.Fonts.body.weight(.bold))
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .foregroundColor(BrockbusterTheme.brockDark)
                                .background(BrockbusterTheme.brockGold)
                                .cornerRadius(12)
                            }
                            .padding(.top, 10)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 28)

                    } else if isLoading {
                        VStack(spacing: 16) {
                            ProgressView("Loading…")
                                .progressViewStyle(CircularProgressViewStyle(tint: BrockbusterTheme.brockGold))
                            Text("Fetching details…")
                                .foregroundColor(colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)
                        }
                        .frame(maxWidth: .infinity, minHeight: 400)
                    } else if let errorMessage = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity, minHeight: 400)
                    }
                }
            }
        }
        .navigationTitle(detail?.name ?? item.name)
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
        .task {
            if detail == nil && !isLoading {
                await loadDetails()
            }
        }
        // Present the video player when a URL is available
        .sheet(item: $playerSheet, onDismiss: {
            // Refresh details after playback so watch state stays accurate.
            Task { await loadDetails() }
        }) { sheet in
            PlayerView(
                itemId: item.id,
                url: sheet.url,
                title: detail?.name ?? item.name,
                subtitle: playbackSubtitle,
                posterURL: session.itemImageURL(for: item, maxWidth: 700)
            )
        }
    }

    // MARK: - Data

    private func loadDetails() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await session.fetchItemDetails(itemId: item.id)
            detail = fetched

            // Best-effort: load cast/crew
            do {
                people = try await session.fetchPeople(for: item.id)
            } catch {
                people = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Playback

    private func playItem() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            do {
                let url = try await session.streamURL(for: item.id)
                await MainActor.run {
                    playbackSubtitle = buildPlaybackSubtitle()
                    playerSheet = PresentedPlayerURL(url: url)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private var playButtonTitle: String {
        switch watchState {
        case .watched:
            return "Play Again"
        case .inProgress:
            return "Resume"
        case .notStarted:
            return "Play"
        }
    }

    private func buildPlaybackSubtitle() -> String {
        var parts: [String] = []
        if let year = detail?.productionYear {
            parts.append(String(year))
        }
        if let ticks = detail?.runTimeTicks {
            parts.append(formatRuntime(ticks))
        }
        if let rating = detail?.communityRating {
            parts.append(String(format: "%.1f★", rating))
        }
        return parts.joined(separator: " • ")
    }

    // MARK: - Watch Status (UserData)

    private enum WatchState {
        case notStarted
        case inProgress
        case watched
    }

    private var resolvedUserData: JellyfinClient.UserData? {
        // Prefer fresh data from detail; fall back to list item if needed.
        return detail?.userData ?? item.userData
    }

    private var shouldShowWatchStatus: Bool {
        // Show if Jellyfin gave us any user data fields (common for episodes).
        return resolvedUserData?.played != nil || (resolvedUserData?.playbackPositionTicks ?? 0) > 0
    }

    private var watchState: WatchState {
        let played = resolvedUserData?.played ?? false
        if played { return .watched }
        let pos = resolvedUserData?.playbackPositionTicks ?? 0
        if pos > 0 { return .inProgress }
        return .notStarted
    }

    private var watchTotalTicks: Int? {
        // Prefer detail runtime; fall back to library item runtime.
        return detail?.runTimeTicks ?? item.runtimeTicks
    }

    private var watchProgressFraction: Double? {
        switch watchState {
        case .watched:
            return 1.0
        case .inProgress:
            let pos = Double(resolvedUserData?.playbackPositionTicks ?? 0)
            guard pos > 0 else { return nil }
            let total = Double(watchTotalTicks ?? 0)
            guard total > 0 else { return nil }
            // Avoid showing "complete" unless played is true.
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
        let pct = Int(frac * 100.0)
        return "\(pct)%"
    }

    private var watchLastPlayedText: String? {
        guard let iso = resolvedUserData?.lastPlayedDate else { return nil }
        if let dt = ISO8601DateFormatter().date(from: iso) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return "Last played: \(df.string(from: dt))"
        }
        return "Last played: \(iso)"
    }

    // MARK: - Formatting helpers

    private func formatRuntime(_ ticks: Int) -> String {
        let seconds = Double(ticks) / 10_000_000.0
        let minutes = Int(seconds) / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(remainingMinutes)m"
        }
    }

    /// Formats ticks into a clock string:
    /// - "mm:ss" if < 1 hour
    /// - "h:mm:ss" if >= 1 hour
    private func formatClockTime(_ ticks: Int) -> String {
        let totalSeconds = Int(Double(ticks) / 10_000_000.0)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return "\(h):" + String(format: "%02d:%02d", m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private var lightModeGradientColors: [Color] {
        #if os(tvOS)
        return [
            BrockbusterTheme.brockDark,
            BrockbusterTheme.brockBlue.opacity(0.14),
            BrockbusterTheme.brockGold.opacity(0.10)
        ]
        #else
        return [
            Color(.systemBackground),
            BrockbusterTheme.brockBlue.opacity(0.14),
            BrockbusterTheme.brockGold.opacity(0.10)
        ]
        #endif
    }
}

// MARK: - Small Components

private struct PresentedPlayerURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// A small pill-shaped label used to display metadata values like year,
/// runtime or rating.
private struct InfoChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(BrockbusterTheme.Fonts.body.weight(.semibold))
            .foregroundColor(BrockbusterTheme.brockDark)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrockbusterTheme.brockGold.opacity(0.8))
            )
    }
}

/// Premium watch-state card with optional progress UI.
private struct WatchStatusCard: View {
    enum State {
        case notStarted
        case inProgress
        case watched
    }

    let state: Any
    let progressFraction: Double?
    let elapsedText: String?
    let totalText: String?
    let percentText: String?
    let lastPlayedText: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: iconName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(iconColor)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrockbusterTheme.textPrimary)

                    Spacer(minLength: 0)

                    if let pct = percentText, title == "In Progress" {
                        Text(pct)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrockbusterTheme.textSecondary)
                    }
                }

                if let progress = progressFraction, title != "Watched" || progress < 1.0 {
                    EpisodeProgressBar(progress: progress)
                }

                if title == "In Progress", let elapsedText, let totalText {
                    Text("\(elapsedText) / \(totalText)")
                        .font(.caption)
                        .foregroundStyle(BrockbusterTheme.textSecondary)
                }

                if title == "Watched", let lastPlayedText {
                    Text(lastPlayedText)
                        .font(.caption)
                        .foregroundStyle(BrockbusterTheme.textSecondary)
                }
            }
        }
    }

    private var title: String {
        // state is passed as Any to avoid leaking parent enum type across file boundaries;
        // determine via iconName mapping below (safe, simple).
        switch iconName {
        case "checkmark.circle.fill":
            return "Watched"
        case "clock.fill":
            return "In Progress"
        default:
            return "Not Started"
        }
    }

    private var iconName: String {
        // Infer from whether progress exists and whether it is complete.
        if let p = progressFraction, p >= 0.999 {
            return "checkmark.circle.fill"
        }
        if (progressFraction ?? 0) > 0 {
            return "clock.fill"
        }
        return "circle"
    }

    private var iconColor: some ShapeStyle {
        if iconName == "checkmark.circle.fill" {
            return BrockbusterTheme.ticketYellow
        }
        if iconName == "clock.fill" {
            return .white.opacity(0.75)
        }
        return .white.opacity(0.45)
    }
}

/// Slim progress bar used in multiple screens.
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
                    .frame(width: max(4, w * max(0, min(progress, 1))), height: 4)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
