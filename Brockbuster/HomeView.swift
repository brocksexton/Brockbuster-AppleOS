import SwiftUI

/// Home feed:
/// - Horizontal library "chips" at the top
/// - Continue Watching
/// - Recently Added (Movies / Shows)
/// - Lazy, scroll-first layout (Netflix/Blockbuster inspired)
///
/// Also includes a first-load welcome overlay to allow the app to preload
/// key data without showing a blank screen.
struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = HomeFeedViewModel()

    var body: some View {
        ZStack {
            background

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header

                    librariesBar

                    if !model.resumeItems.isEmpty {
                        HomeSection(title: "Continue Watching") {
                            HomeRail(items: model.resumeItems) { item in
                                AnyView(ItemDetailView(item: item).environmentObject(session))
                            }
                        }
                    }

                    if !model.recentMovies.isEmpty {
                        HomeSection(title: "Recently Added • Movies") {
                            HomeRail(items: model.recentMovies) { item in
                                AnyView(ItemDetailView(item: item).environmentObject(session))
                            }
                        }
                    }

                    if !model.recentShows.isEmpty {
                        HomeSection(title: "Recently Added • TV") {
                            HomeRail(items: model.recentShows) { item in
                                let type = (item.type ?? "").lowercased()
                                if type == "series" {
                                    return AnyView(SeriesDetailView(series: item).environmentObject(session))
                                }
                                return AnyView(ItemDetailView(item: item).environmentObject(session))
                            }
                        }
                    }

                    // Actions
                    HStack(spacing: 14) {
                        Button(action: session.logout) {
                            Text("Log Out")
                                .font(BrockbusterTheme.Fonts.body.weight(.bold))
                                .foregroundColor(BrockbusterTheme.brockDark)
                        }
                        .buttonStyle(BrockbusterTheme.TicketButtonStyle())

                        Button(action: session.resetServer) {
                            Text("Change Server")
                                .font(BrockbusterTheme.Fonts.body.weight(.bold))
                                .foregroundColor(BrockbusterTheme.brockDark)
                        }
                        .buttonStyle(BrockbusterTheme.TicketButtonStyle())
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 22)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            if model.isPreloading {
                WelcomePreloadOverlay(
                    userName: session.currentUser?.name,
                    profileURL: session.userProfileImageURL(maxWidth: 160),
                    slogan: model.slogan,
                    progress: model.preloadProgress
                )
                .transition(.opacity)
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.bootstrapIfNeeded(session: session)
        }
    }

    // MARK: - Subviews

    private var background: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                BrockbusterTheme.brockDark.opacity(0.6),
                BrockbusterTheme.brockBlue.opacity(0.6)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if let url = session.userProfileImageURL(maxWidth: 120) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 54, height: 54)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 54, height: 54)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(BrockbusterTheme.brockGold, lineWidth: 2))
                    case .failure:
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 54, height: 54)
                            .foregroundColor(BrockbusterTheme.brockGold)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if let user = session.currentUser {
                    Text("Welcome, \(user.name)")
                        .font(BrockbusterTheme.Fonts.title)
                        .foregroundColor(BrockbusterTheme.brockLight)
                }
                Text(model.slogan)
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 6)
    }

    private var librariesBar: some View {
        Group {
            if session.isFetchingLibraries && session.libraries.isEmpty {
                HStack {
                    ProgressView("Loading libraries…")
                        .progressViewStyle(CircularProgressViewStyle(tint: BrockbusterTheme.brockGold))
                        .foregroundColor(BrockbusterTheme.brockGold)
                    Spacer()
                }
            } else if session.libraries.isEmpty {
                Text("No libraries found.")
                    .foregroundColor(BrockbusterTheme.brockLight)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(session.libraries) { library in
                            NavigationLink(destination: LibraryDetailView(library: library).environmentObject(session)) {
                                LibraryChip(
                                    title: library.name,
                                    imageURL: session.libraryImageURL(for: library, maxWidth: 260)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class HomeFeedViewModel: ObservableObject {
    @Published var isPreloading: Bool = true
    @Published var preloadProgress: Double = 0.0

    @Published var slogan: String = HomeFeedViewModel.randomSlogan()

    @Published var resumeItems: [JellyfinClient.LibraryItem] = []
    @Published var recentMovies: [JellyfinClient.LibraryItem] = []
    @Published var recentShows: [JellyfinClient.LibraryItem] = []

    private var hasBootstrapped = false

    func bootstrapIfNeeded(session: SessionStore) async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        // Random slogan per load
        slogan = Self.randomSlogan()

        // Step 1: Libraries
        preloadProgress = 0.08
        if session.isLoggedIn && session.libraries.isEmpty {
            do {
                try await session.fetchLibraries()
            } catch {
                // Non-fatal; the UI will show "No libraries found".
            }
        }
        preloadProgress = 0.34

        // Identify libraries (heuristic based on name)
        let libs = session.libraries
        let movieLib = libs.first(where: { $0.name.lowercased().contains("movie") })
        let tvLib = libs.first(where: { $0.name.lowercased().contains("tv") || $0.name.lowercased().contains("show") })

        // Step 2: Continue watching (resume)
        do {
            resumeItems = try await session.fetchResumeItems(limit: 18)
        } catch {
            resumeItems = []
        }
        preloadProgress = 0.58

        // Step 3: Recently Added (Movies)
        if let movieLib {
            do {
                recentMovies = try await session.fetchItemsPage(
                    parentId: movieLib.id,
                    includeItemTypes: ["Movie"],
                    sortBy: ["DateCreated"],
                    sortOrder: "Descending",
                    limit: 20,
                    recursive: true
                )
            } catch {
                recentMovies = []
            }
        }
        preloadProgress = 0.78

        // Step 4: Recently Added (Series)
        if let tvLib {
            do {
                recentShows = try await session.fetchItemsPage(
                    parentId: tvLib.id,
                    includeItemTypes: ["Series"],
                    sortBy: ["DateCreated"],
                    sortOrder: "Descending",
                    limit: 20,
                    recursive: true
                )
            } catch {
                recentShows = []
            }
        }

        preloadProgress = 1.0
        withAnimation(.easeInOut(duration: 0.25)) {
            isPreloading = false
        }
    }

    private static func randomSlogan() -> String {
        let slogans = [
            "Be kind. Rewind.",
            "Tonight's feature presentation awaits.",
            "Pick your flick and press play.",
            "Your couch just became a Blockbuster.",
            "Now playing: whatever you want.",
            "Browse, queue, and roll the tape.",
            "New releases, old favorites, no late fees.",
            "Grab some popcorn — let's start the show.",
            "Your next rental is one tap away.",
            "Lights down. Volume up."
        ]
        return slogans.randomElement() ?? "Be kind. Rewind."
    }
}

// MARK: - Components

private struct LibraryChip: View {
    let title: String
    let imageURL: URL?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.10))
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().tint(BrockbusterTheme.brockGold)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "film")
                                .foregroundColor(.white.opacity(0.65))
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "film")
                        .foregroundColor(.white.opacity(0.65))
                }
            }
            .frame(width: 54, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                .font(BrockbusterTheme.Fonts.body.weight(.semibold))
                .foregroundColor(BrockbusterTheme.brockLight)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(BrockbusterTheme.brockGold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BrockbusterTheme.brockBlue.opacity(0.40), lineWidth: 1)
        )
    }
}

private struct HomeSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BrockbusterTheme.Fonts.title)
                .foregroundColor(BrockbusterTheme.brockLight)
            content()
        }
        .padding(.top, 6)
    }
}

private struct HomeRail: View {
    @EnvironmentObject private var session: SessionStore
    let items: [JellyfinClient.LibraryItem]
    let destination: (JellyfinClient.LibraryItem) -> AnyView

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink(destination: destination(item).environmentObject(session)) {
                        HomePosterCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct HomePosterCard: View {
    @EnvironmentObject private var session: SessionStore
    let item: JellyfinClient.LibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                if let url = session.itemImageURL(for: item, maxWidth: 420) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(.white.opacity(0.08))
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Rectangle()
                                .fill(.white.opacity(0.08))
                                .overlay(Image(systemName: "film").foregroundColor(.white.opacity(0.55)))
                        @unknown default:
                            Rectangle().fill(.white.opacity(0.08))
                        }
                    }
                } else {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .overlay(Image(systemName: "film").foregroundColor(.white.opacity(0.55)))
                }

                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.75)]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if let ud = item.userData,
                       let pos = ud.playbackPositionTicks,
                       pos > 0,
                       (ud.played ?? false) == false {
                        Text("Resume")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(BrockbusterTheme.brockGold)
                    }
                }
                .padding(8)
            }
            .frame(width: 140, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
        }
    }
}

private struct WelcomePreloadOverlay: View {
    let userName: String?
    let profileURL: URL?
    let slogan: String
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 14) {
                if let url = profileURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Circle()
                                .fill(.white.opacity(0.12))
                                .frame(width: 86, height: 86)
                                .overlay(ProgressView().tint(BrockbusterTheme.brockGold))
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 86, height: 86)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(BrockbusterTheme.brockGold, lineWidth: 3))
                        case .failure:
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 86, height: 86)
                                .foregroundColor(BrockbusterTheme.brockGold)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                Text(userName.map { "Welcome, \($0)" } ?? "Welcome")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Text(slogan)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                ProgressView(value: min(max(progress, 0), 1))
                    .tint(BrockbusterTheme.brockGold)
                    .frame(width: 220)

                Text("Loading your shelf…")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.70))
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }
}
