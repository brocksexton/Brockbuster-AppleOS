import SwiftUI

/// Displays the media items contained in a collection (box set).  A collection
/// is represented by a `LibraryItem` with mediaType "BoxSet" or "CollectionFolder".
/// The view fetches the items via `SessionStore.fetchItems` using the
/// collection's id as the parent.  Items are presented in a grid similar to
/// `LibraryDetailView`.  You can filter using a search bar and letter filter.
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

    /// Filter items based on search and letter filters
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

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.5), BrockbusterTheme.brockBlue.opacity(0.5)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading) {
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
                HStack {
                    TextField("Search", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(BrockbusterTheme.brockGold)
                        }
                        .padding(.trailing)
                    }
                }
                .padding(.top, 4)
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
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 4)
                if isLoading {
                    Spacer()
                    ProgressView("Loading…")
                        .progressViewStyle(CircularProgressViewStyle(tint: BrockbusterTheme.brockGold))
                    Spacer()
                } else if let errorMessage = errorMessage {
                    Spacer()
                    Text(errorMessage).foregroundColor(.red).padding()
                    Spacer()
                } else if filteredItems.isEmpty {
                    Spacer()
                    Text("No items found.").foregroundColor(BrockbusterTheme.brockLight)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridLayout, spacing: 16) {
                            ForEach(filteredItems) { item in
                                NavigationLink(destination: destinationView(for: item).environmentObject(session)) {
                                    ZStack(alignment: .bottomLeading) {
                                        if let url = session.itemImageURL(for: item, maxWidth: 400) {
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
                                        } else {
                                            Rectangle().fill(BrockbusterTheme.brockDark.opacity(0.3))
                                        }
                                        LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                                        Text(item.name)
                                            .font(BrockbusterTheme.Fonts.body.weight(.bold))
                                            .foregroundColor(.white)
                                            .padding(8)
                                    }
                                    .frame(height: 200)
                                    .cornerRadius(12)
                                    .clipped()
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding([.horizontal, .bottom])
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: filteredItems.count)
                    }
                }
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
                    url: url,
                    title: playbackTitle,
                    subtitle: playbackSubtitle,
                    posterURL: session.itemImageURL(for: collection, maxWidth: 700)
                )
            }
        }
    }

    /// Determine destination view depending on media type
    private func destinationView(for item: JellyfinClient.LibraryItem) -> some View {
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

    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await session.fetchItems(for: collection)
            items = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Play the collection by starting playback of the first playable item
    private func playCollection() async {
        // Load items if needed
        if items.isEmpty {
            await loadItems()
        }

        // Choose a playable item: prefer Episodes or Movies if present
        let playable = items.first(where: { ($0.mediaType ?? "").localizedCaseInsensitiveContains("episode") || ($0.mediaType ?? "").localizedCaseInsensitiveContains("movie") }) ?? items.first

        guard let item = playable else {
            await MainActor.run { self.errorMessage = "No items available to play." }
            return
        }

        // Attempt to obtain a stream URL from the session
        var url: URL? = nil

        // TODO: If your SessionStore exposes a different API to build stream URLs, replace this block accordingly.
        // Common patterns could be: session.streamURL(for:), session.playbackURL(for:), or session.getStreamURL(for:)
        if let streamURL = await (session as AnyObject).perform?(Selector(("streamURLFor:"))) as? URL {
            url = streamURL
        }

        // Fallback: Try calling a few known selectors dynamically if available
        if url == nil {
            // Try common method names via optional chaining wrappers
            if let sessionObj = session as AnyObject?, sessionObj.responds(to: Selector(("streamURLForItem:"))) {
                // This is just a placeholder; without a known signature we can't invoke it directly.
                // Leave url as nil; developer should wire up the correct call below.
            }
        }

        // If no dynamic method found, give up with a friendly message
        guard let finalURL = url else {
            await MainActor.run { self.errorMessage = "Unable to build a stream URL for this item. Please wire playCollection() to your SessionStore's streaming API." }
            return
        }

        // Present the player
        await MainActor.run {
            self.playerURL = finalURL
            self.playbackTitle = item.name
            self.playbackSubtitle = item.productionYear.flatMap { String($0) }
            self.showPlayer = true
        }
    }
}

// Preview intentionally omitted to avoid keeping a second copy of the model
// initializer signature in sync with Jellyfin schema changes.

