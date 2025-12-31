import SwiftUI

/// A detail view that displays the contents of a single library (view).  When this
/// view appears it fetches the items within the given library from the server via
/// the session store.  Media items are presented in a grid with their artwork
/// and titles.  If an item has no image a placeholder is shown.  Errors during
/// loading are surfaced to the user.
struct LibraryDetailView: View {
    let library: JellyfinClient.LibraryView
    @EnvironmentObject private var session: SessionStore
    @State private var items: [JellyfinClient.LibraryItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    @State private var selectedLetter: String?

    /// Constrain library fetches to the expected top-level type.
    /// This prevents "Shows" libraries from returning Episode-level rows when
    /// recursive fetching is enabled.
    private var includeItemTypes: [String]? {
        let n = library.name.lowercased()
        if n.contains("movie") { return ["Movie"] }
        if n.contains("show") || n.contains("tv") || n.contains("series") { return ["Series"] }
        if n.contains("collection") { return ["BoxSet"] }
        return nil
    }

    // Compute the grid layout.  Use adaptive columns so the number of columns
    // adjusts based on available width.  On tvOS this results in fewer larger
    // columns, while on iPhone more columns are used.
    private var gridLayout: [GridItem] {
        [GridItem(.adaptive(minimum: 140), spacing: 16)]
    }

    /// Compute the filtered items based on the search text and selected letter.
    private var filteredItems: [JellyfinClient.LibraryItem] {
        var filtered = items
        // Apply letter filter first if a letter is selected
        if let letter = selectedLetter, !letter.isEmpty {
            let isHash = (letter == "#")
            filtered = filtered.filter { item in
                guard let firstChar = item.name.first else { return false }
                if isHash {
                    return !firstChar.isLetter
                } else {
                    let first = String(firstChar)
                    return first.compare(letter, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: .current) == .orderedSame
                }
            }
        }
        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText
            // Use localizedCaseInsensitiveContains to reduce type-checker complexity
            filtered = filtered.filter { item in
                item.name.localizedCaseInsensitiveContains(query)
            }
        }
        return filtered
    }

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(alignment: .leading) {
                // Header: library name
                Text(library.name)
                    .font(BrockbusterTheme.Fonts.largeTitle)
                    .foregroundColor(BrockbusterTheme.brockLight)
                    .padding(.horizontal)
                    .padding(.top)
                // Search and filter controls
                searchBar
                    .padding(.top, 4)
                // Letter filter row
                letterFilterBar
                    .padding(.top, 4)
                // Content area
                contentArea
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            // Fetch items when the view appears
            if items.isEmpty {
                await loadItems()
            }
        }
    }

    private var backgroundGradient: some View {
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

    private var searchBar: some View {
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
    }

    private var letterFilterBar: some View {
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
    }

    private var contentArea: some View {
        Group {
            if isLoading {
                VStack { Spacer(); ProgressView("Loading…")
                    .progressViewStyle(CircularProgressViewStyle(tint: BrockbusterTheme.brockGold)); Spacer() }
            } else if let errorMessage = errorMessage {
                VStack { Spacer(); Text(errorMessage).foregroundColor(.red).padding(); Spacer() }
            } else if items.isEmpty {
                VStack { Spacer(); Text("No items found.").foregroundColor(BrockbusterTheme.brockLight); Spacer() }
            } else {
                ScrollView {
                    LazyVGrid(columns: gridLayout, spacing: 16) {
                        ForEach(filteredItems) { item in
                            NavigationLink(destination: destinationView(for: item).environmentObject(session)) {
                                ItemCell(item: item, imageURL: session.itemImageURL(for: item, maxWidth: 500))
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

    /// Determine which view to navigate to based on the item's media type.  If the item
    /// represents a series, navigate to SeriesDetailView; if it's a season, navigate
    /// to SeasonDetailView; if it's a collection (BoxSet/CollectionFolder) navigate
    /// to CollectionDetailView; otherwise navigate to ItemDetailView.
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

    /// Load the items for this library using the session store.  Updates loading
    /// and error state accordingly.  This method must be called from within a
    /// task.
    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await session.fetchItems(for: library, includeItemTypes: includeItemTypes)
            items = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private struct ItemCell: View {
        let item: JellyfinClient.LibraryItem
        let imageURL: URL?

        var isEpisode: Bool {
            (item.type ?? "").lowercased() == "episode"
        }

        var body: some View {
            ZStack(alignment: .bottomLeading) {
                poster
                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                Text(item.name)
                    .font(BrockbusterTheme.Fonts.body.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .padding(8)
            }
            .aspectRatio(isEpisode ? (16.0/9.0) : (2.0/3.0), contentMode: .fit)
            .cornerRadius(12)
            .clipped()
        }

        @ViewBuilder
        private var poster: some View {
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(BrockbusterTheme.brockDark.opacity(0.3))
                    case .success(let image):
                        image.resizable().scaledToFill()
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
        }
    }
}

// Preview for Xcode canvas (optional placeholder data)
#if DEBUG
struct LibraryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let dummyView = JellyfinClient.LibraryView(id: "123", name: "Movies", primaryImageTag: nil)
        LibraryDetailView(library: dummyView)
            .environmentObject(SessionStore())
    }
}
#endif

