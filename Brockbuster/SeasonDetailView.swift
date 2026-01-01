import SwiftUI

/// Displays the episodes within a season.  The season is represented by
/// a `LibraryItem` with mediaType "Season".  This view fetches the child
/// items (episodes) using `SessionStore.fetchItems`.  Episodes are shown
/// in a list with poster artwork and title.  A search field is provided
/// to filter episodes quickly.
struct SeasonDetailView: View {
    let season: JellyfinClient.LibraryItem
    @EnvironmentObject private var session: SessionStore
    @State private var episodes: [JellyfinClient.LibraryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText: String = ""

    /// Filter episodes based on search text
    private var filteredEpisodes: [JellyfinClient.LibraryItem] {
        if searchText.isEmpty { return episodes }
        return episodes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.5), BrockbusterTheme.brockBlue.opacity(0.5)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading) {
                Text(season.name)
                    .font(BrockbusterTheme.Fonts.largeTitle)
                    .foregroundColor(BrockbusterTheme.brockLight)
                    .padding(.horizontal)
                    .padding(.top)
                // Search field
                HStack {
                    TextField("Search episodes", text: $searchText)
                        .bbTextFieldStyle()
                        .padding(.horizontal)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(BrockbusterTheme.brockGold)
                        }
                        .padding(.trailing)
                    }
                }
                .padding(.top, 4)
                // Episodes list
                if isLoading {
                    Spacer()
                    ProgressView("Loading episodes…")
                        .progressViewStyle(CircularProgressViewStyle(tint: BrockbusterTheme.brockGold))
                    Spacer()
                } else if let errorMessage = errorMessage {
                    Spacer()
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                    Spacer()
                } else if filteredEpisodes.isEmpty {
                    Spacer()
                    Text("No episodes found.")
                        .foregroundColor(BrockbusterTheme.brockLight)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredEpisodes) { episode in
                                NavigationLink(destination: ItemDetailView(item: episode).environmentObject(session)) {
                                    HStack(spacing: 16) {
                                        if let url = session.itemImageURL(for: episode, maxWidth: 300) {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .empty:
                                                    Rectangle().fill(BrockbusterTheme.brockDark.opacity(0.3))
                                                case .success(let image):
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                case .failure:
                                                    Rectangle().fill(BrockbusterTheme.brockDark.opacity(0.3)).overlay(Image(systemName: "film.fill").foregroundColor(BrockbusterTheme.brockGold))
                                                @unknown default:
                                                    EmptyView()
                                                }
                                            }
                                            .frame(width: 100, height: 60)
                                            .clipped()
                                            .cornerRadius(8)
                                        } else {
                                            Rectangle().fill(BrockbusterTheme.brockDark.opacity(0.3))
                                                .frame(width: 100, height: 60)
                                                .cornerRadius(8)
                                        }
                                        VStack(alignment: .leading) {
                                            Text(episode.name)
                                                .font(BrockbusterTheme.Fonts.title)
                                                .foregroundColor(BrockbusterTheme.brockLight)
                                        }
                                        Spacer()
                                        Image(systemName: "play.circle.fill").foregroundColor(BrockbusterTheme.brockGold)
                                    }
                                    .padding()
                                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(BrockbusterTheme.brockBlue.opacity(0.4), lineWidth: 1))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding([.horizontal, .bottom])
                    }
                }
            }
        }
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
        .navigationTitle(season.name)
        .task {
            if episodes.isEmpty {
                await loadEpisodes()
            }
        }
    }

    private func loadEpisodes() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await session.fetchItems(for: season)
            episodes = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#if DEBUG
struct SeasonDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let dummySeason = JellyfinClient.LibraryItem(
            id: "sea123",
            name: "Season 1",
            type: "Season",
            mediaType: "Season",
            runtimeTicks: nil,
            primaryImageTag: nil,
            overview: nil,
            productionYear: nil,
            indexNumber: 1,
            parentIndexNumber: nil,
            seriesId: nil,
            seasonId: nil,
            seriesName: nil,
            userData: nil
        )

        SeasonDetailView(season: dummySeason)
            .environmentObject(SessionStore())
    }
}
#endif
