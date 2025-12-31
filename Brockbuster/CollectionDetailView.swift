import SwiftUI

/// Displays the media items contained in a collection (box set).
/// A collection is represented by a `LibraryItem` with type/mediaType like "BoxSet" or "CollectionFolder".
/// The view fetches the items via `SessionStore.fetchItems(for:)` using the collection's id as the parent.
/// Items are presented in a grid similar to `LibraryDetailView`. You can filter using a search bar and letter filter.
struct CollectionDetailView: View {
    let collection: JellyfinClient.LibraryItem

    @EnvironmentObject private var session: SessionStore

    @State private var items: [JellyfinClient.LibraryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var showPlayer: Bool = false
    @State private var playerURL: URL?
    @State private var playbackTitle: String = ""
    @State private var playbackSubtitle: String? = nil

    @State private var searchText: String = ""
    @State private var selectedLetter: String?

    // MARK: - Filtering

    private var filteredItems: [JellyfinClient.LibraryItem] {
        var filtered = items

        if let letter = selectedLetter, !letter.isEmpty {
            filtered = filtered.filter { item in
                guard let first = item.name.first else { return false }
                if letter == "#" {
                    return !first.isLetter
                } else {
                    return String(first).localizedCaseInsensitiveCompare(letter) == .orderedSame
                }
            }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return filtered
    }

    private var gridLayout: [GridItem] {
        [GridItem(.adaptive(minimum: 140), spacing: 16)]
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 12) {
                headerRow
                searchRow
                letterFilterRow
                contentArea
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle(collection.name)
        .task {
            if items.isEmpty {
                await loadItems()
            }
        }
        .sheet(isPresented: $showPlayer) {
            if let url = playerURL {
                PlayerView(
                    itemId: collection.id,
                    url: url,
                    title: playbackTitle,
                    subtitle: playbackSubtitle,
                    posterURL: session.itemImageURL(for: collection, maxWidth: 700)
                )
            }
        }
    }

    // MARK: - Subviews (to avoid compiler type-check timeout)

    private var background: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                BrockbusterTheme.brockDark.opacity(0.5),
                BrockbusterTheme.brockBlue.opacity(0.5)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text(collection.name)
                .font(BrockbusterTheme.Fonts.largeTitle)
                .foregroundColor(BrockbusterTheme.brockLight)

            Spacer()

            Button(action: { Task { await playCollection() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Play")
                        .font(BrockbusterTheme.Fonts.body.weight(.bold))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .foregroundColor(BrockbusterTheme.brockDark)
                .background(BrockbusterTheme.brockGold)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top)
    }

    private var searchRow: some View {
        HStack {
            TextField("Search", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(BrockbusterTheme.brockGold)
                }
                .padding(.trailing)
            }
        }
        .padding(.top, 4)
    }

    private var letterFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["#"] + Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map { String($0) }, id: \.self) { letter in
                    Button(action: {
                        if selectedLetter == letter {
                            selectedLetter = nil
                        } else {
                            selectedLetter = letter
                        }
                    }) {
                        Text(letter)
                            .font(BrockbusterTheme.Fonts.body.weight(.semibold))
                            .foregroundColor(selectedLetter == letter ? BrockbusterTheme.brockDark : BrockbusterTheme.brockLight)
                            .frame(width: 28, height: 28)
                            .background(selectedLetter == letter ? BrockbusterTheme.brockGold : BrockbusterTheme.brockDark.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 4)
    }

    private var contentArea: some View {
        Group {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading…")
                        .progressViewStyle(CircularProgressViewStyle(tint: BrockbusterTheme.brockGold))
                    Spacer()
                }
            } else if let errorMessage = errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                    Spacer()
                }
            } else if filteredItems.isEmpty {
                VStack {
                    Spacer()
                    Text("No items found.")
                        .foregroundColor(BrockbusterTheme.brockLight)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: gridLayout, spacing: 16) {
                        ForEach(filteredItems) { item in
                            NavigationLink(destination: destinationView(for: item).environmentObject(session)) {
                                itemCard(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding([.horizontal, .bottom])
                }
            }
        }
    }

    private func itemCard(_ item: JellyfinClient.LibraryItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let url = session.itemImageURL(for: item, maxWidth: 400) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(BrockbusterTheme.brockDark.opacity(0.3))
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .fill(BrockbusterTheme.brockDark.opacity(0.3))
                            .overlay(Image(systemName: "film.fill").foregroundColor(BrockbusterTheme.brockGold))
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Rectangle().fill(BrockbusterTheme.brockDark.opacity(0.3))
            }

            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)]),
                startPoint: .top,
                endPoint: .bottom
            )

            Text(item.name)
                .font(BrockbusterTheme.Fonts.body.weight(.bold))
                .foregroundColor(.white)
                .padding(8)
        }
        .frame(height: 200)
        .cornerRadius(12)
        .clipped()
    }

    // MARK: - Navigation

    private func destinationView(for item: JellyfinClient.LibraryItem) -> AnyView {
        let type = (item.type ?? "").lowercased()
        switch type {
        case "series":
            return AnyView(SeriesDetailView(series: item))
        case "season":
            return AnyView(SeasonDetailView(season: item))
        case "boxset", "collectionfolder", "collection":
            return AnyView(CollectionDetailView(collection: item))
        default:
            return AnyView(ItemDetailView(item: item))
        }
    }

    // MARK: - Data

    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            items = try await session.fetchItems(for: collection)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Playback

    /// Play the collection by starting playback of the first playable item.
    /// - If the first item is a Series, resolve NextUp/S1E1 via SessionStore helper.
    /// - Otherwise play the first item directly.
    private func playCollection() async {
        if items.isEmpty {
            await loadItems()
        }

        guard let firstItem = items.first else {
            await MainActor.run { self.errorMessage = "No items available to play." }
            return
        }

        do {
            let firstType = (firstItem.type ?? "").lowercased()
            let targetId: String

            if firstType == "series" {
                // Prefer "Next Up" / Resume style episode if available; otherwise first episode.
                if let ep = try await session.resolvePrimaryEpisodeForSeries(seriesId: firstItem.id) {
                    targetId = ep.id
                    await MainActor.run {
                        self.playbackTitle = firstItem.name
                        self.playbackSubtitle = episodeSubtitle(ep)
                    }
                } else {
                    targetId = firstItem.id
                    await MainActor.run {
                        self.playbackTitle = firstItem.name
                        self.playbackSubtitle = nil
                    }
                }
            } else {
                targetId = firstItem.id
                await MainActor.run {
                    self.playbackTitle = firstItem.name
                    self.playbackSubtitle = firstItem.productionYear.map(String.init)
                }
            }

            let url = try await session.streamURL(for: targetId)

            await MainActor.run {
                self.playerURL = url
                self.showPlayer = true
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

    private func episodeSubtitle(_ ep: JellyfinClient.LibraryItem) -> String {
        var parts: [String] = []
        if let s = ep.parentIndexNumber, s > 0 { parts.append("S\(s)") }
        if let e = ep.indexNumber, e > 0 { parts.append("E\(e)") }
        let se = parts.joined()
        if se.isEmpty { return ep.name }
        return "\(se) • \(ep.name)"
    }
}
