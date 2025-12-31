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
                Text(collection.name)
                    .font(BrockbusterTheme.Fonts.largeTitle)
                    .foregroundColor(BrockbusterTheme.brockLight)
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
    }

    /// Determine destination view depending on media type
    private func destinationView(for item: JellyfinClient.LibraryItem) -> some View {
        // Determine if the item is a series, season or normal item
        if let mediaType = item.mediaType?.lowercased() {
            if mediaType == "series" {
                return AnyView(SeriesDetailView(series: item))
            } else if mediaType == "season" {
                return AnyView(SeasonDetailView(season: item))
            }
        }
        // Default to item detail view
        return AnyView(ItemDetailView(item: item))
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
}

// Preview intentionally omitted to avoid keeping a second copy of the model
// initializer signature in sync with Jellyfin schema changes.
