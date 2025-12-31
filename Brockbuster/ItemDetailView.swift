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
                        // Title and tagline
                        Text(detail.name)
                            .font(BrockbusterTheme.Fonts.largeTitle)
                            .foregroundColor(BrockbusterTheme.brockLight)
                        if let taglines = detail.taglines, let first = taglines.first, !first.isEmpty {
                            Text(first)
                                .font(BrockbusterTheme.Fonts.body)
                                .foregroundColor(BrockbusterTheme.brockGold)
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
                PlayerView(url: url)
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

#if DEBUG
struct ItemDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let dummyItem = JellyfinClient.LibraryItem(
            id: "123",
            name: "Sample Movie",
            mediaType: "Movie",
            // type: "Movie",
            overview: "A sample overview for previewing the item detail page.",
            productionYear: 2024,
            indexNumber: nil,
            parentIndexNumber: nil,
            runtimeTicks: 3600 * 10_000_000,
            primaryImageTag: nil
        )

        ItemDetailView(item: dummyItem)
            .environmentObject(SessionStore())
    }
}
#endif
