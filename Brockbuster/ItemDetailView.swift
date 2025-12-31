import SwiftUI

/// Displays detailed information about a single media item.  The view fetches
/// additional metadata from the server when it appears and shows a large
/// poster, title, runtime, year and overview.  A placeholder message is
/// displayed while loading or if an error occurs.  In future versions this
/// view could include playback controls or a "play" button once streaming
/// integration is implemented.
struct ItemDetailView: View {
    /// The basic library item used to identify the item to fetch.  Contains
    /// minimal information such as id and name.
    let item: JellyfinClient.LibraryItem
    @EnvironmentObject private var session: SessionStore
    @State private var detail: JellyfinClient.ItemDetail?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var people: [JellyfinClient.Person] = []
    @State private var playbackSubtitle: String = ""
    // State for presenting the video player
    @State private var showPlayer: Bool = false
    @State private var playerURL: URL?

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.8), BrockbusterTheme.brockBlue.opacity(0.8)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let detail = detail {
                        // Poster image
                        if let url = session.itemImageURL(for: detail, maxWidth: 800) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    Rectangle()
                                        .fill(BrockbusterTheme.brockDark.opacity(0.3))
                                        .frame(height: 300)
                                        .cornerRadius(16)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 300)
                                        .clipped()
                                        .cornerRadius(16)
                                case .failure:
                                    Rectangle()
                                        .fill(BrockbusterTheme.brockDark.opacity(0.3))
                                        .frame(height: 300)
                                        .overlay(Image(systemName: "film.fill").foregroundColor(BrockbusterTheme.brockGold))
                                        .cornerRadius(16)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                        // Title
                        Text(detail.name)
                            .font(BrockbusterTheme.Fonts.largeTitle)
                            .foregroundColor(BrockbusterTheme.brockLight)
                        if let tagline = detail.taglines?.first, !tagline.isEmpty {
                            Text(tagline)
                                .font(.title3.weight(.semibold))
                                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.9))
                                .padding(.top, -10)
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
                        // Genres
                        if let genres = detail.genres, !genres.isEmpty {
                            Text(genres.joined(separator: ", "))
                                .font(BrockbusterTheme.Fonts.body)
                                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                        }
                        // Overview
                        if let overview = detail.overview {
                            Text(overview)
                                .font(BrockbusterTheme.Fonts.body)
                                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
// Cast
let cast = people.filter { ($0.type ?? "").lowercased().contains("actor") || ($0.role ?? "").isEmpty == false }
if !cast.isEmpty {
    VStack(alignment: .leading, spacing: 10) {
        Text("Cast")
            .font(.headline)
            .foregroundColor(BrockbusterTheme.brockLight)

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
                            .foregroundColor(BrockbusterTheme.brockLight)
                            .lineLimit(1)

                        if let role = person.role, !role.isEmpty {
                            Text(role)
                                .font(.caption2)
                                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.75))
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
                                Text("Play")
                                    .font(BrockbusterTheme.Fonts.body.weight(.bold))
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .foregroundColor(BrockbusterTheme.brockDark)
                            .background(BrockbusterTheme.brockGold)
                            .cornerRadius(12)
                        }
                        .padding(.top, 16)
                    } else if isLoading {
                        VStack(spacing: 16) {
                            ProgressView("Loading…")
                                .progressViewStyle(CircularProgressViewStyle(tint: BrockbusterTheme.brockGold))
                            Text("Fetching details…")
                                .foregroundColor(BrockbusterTheme.brockLight)
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
                .padding()
            }
        }
        .navigationTitle(detail?.name ?? item.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            // Load details on appear if not already loaded
            if detail == nil && !isLoading {
                await loadDetails()
            }
        }
        // Present the video player when a URL is available
        .sheet(isPresented: $showPlayer) {
            if let url = playerURL {
                PlayerView(
                    itemId: item.id,
                    url: url,
                    title: detail?.name ?? item.name,
                    subtitle: playbackSubtitle,
                    posterURL: session.itemImageURL(for: item, maxWidth: 700)
                )
            }
        }
    }

    /// Fetch the item details from the server and update state.
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
                // Non-fatal
                people = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Format runtime ticks (100-nanosecond increments) into a human-readable
    /// duration string in hours and minutes.
    private func formatRuntime(_ ticks: Int) -> String {
        // One tick = 100 ns; convert to seconds
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

    /// Attempt to fetch a streaming URL for the item and present the player.
    private func playItem() {
        guard !isLoading else { return }
        // Show loading overlay while fetching the stream URL
        isLoading = true
        Task {
            do {
                let url = try await session.streamURL(for: item.id)
                playerURL = url
                playbackSubtitle = buildPlaybackSubtitle()
                showPlayer = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Build a subtitle string for playback UI using available metadata.
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

    /// Optional: Play a collection (season/series/album) if invoked elsewhere.
    /// Provides a basic implementation mirroring `playItem()` to satisfy references.
    private func playCollection() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            do {
                let url = try await session.streamURL(for: item.id)
                playerURL = url
                playbackSubtitle = buildPlaybackSubtitle()
                showPlayer = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

/// A small pill-shaped label used to display metadata values like year,
/// runtime or rating.  Each chip uses the accent colour and a subtle
/// translucent background for contrast.
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

