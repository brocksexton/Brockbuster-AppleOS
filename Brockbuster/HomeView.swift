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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            background

            GeometryReader { geo in
                #if os(tvOS)
                let contentWidth = min(1400, max(0, geo.size.width - 120))
                #else
                let contentWidth = min(820, max(0, geo.size.width - 32))
                #endif

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header
                        librariesBar

                        Group {
                            if !model.resumeItems.isEmpty {
                                HomeSection(title: "Continue Watching", style: .card) {
                                    HomeRail(items: model.resumeItems) { item in
                                        ItemDetailView(item: item).environmentObject(session)
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            } else if model.isLoadingResume {
                                HomeSection(title: "Continue Watching", style: .card) {
                                    HomeRailPlaceholder()
                                }
                                .transition(.opacity)
                            }
                        }

                        Group {
                            if !model.recentMovies.isEmpty {
                                HomeSection(title: "Recently Added • Movies", style: .card) {
                                    HomeRail(items: model.recentMovies) { item in
                                        ItemDetailView(item: item).environmentObject(session)
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            } else if model.isLoadingRecentMovies {
                                HomeSection(title: "Recently Added • Movies", style: .card) {
                                    HomeRailPlaceholder()
                                }
                                .transition(.opacity)
                            }
                        }

                        Group {
                            if !model.recentShows.isEmpty {
                                HomeSection(title: "Recently Added • TV", style: .card) {
                                    HomeRail(items: model.recentShows) { item in
                                        let type = (item.type ?? "").lowercased()
                                        if type == "series" {
                                            SeriesDetailView(series: item).environmentObject(session)
                                        } else {
                                            ItemDetailView(item: item).environmentObject(session)
                                        }
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            } else if model.isLoadingRecentShows {
                                HomeSection(title: "Recently Added • TV", style: .card) {
                                    HomeRailPlaceholder()
                                }
                                .transition(.opacity)
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
                        .padding(.top, 10)
                        .padding(.bottom, 26)
                    }
                    .frame(maxWidth: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                }
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
        .bbNavigationTitleInline()
        .task {
            await model.bootstrapIfNeeded(session: session)
        }
    }

    // MARK: - Subviews

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

    private var background: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    gradient: Gradient(colors: [
                        BrockbusterTheme.brockDark.opacity(0.62),
                        BrockbusterTheme.brockBlue.opacity(0.62)
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
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if let url = session.userProfileImageURL(maxWidth: 120) {
                BBCachedAsyncImage(url: url, targetSize: CGSize(width: 108, height: 108)) { phase in
                    switch phase {
                    case .empty:
                        AnyView(ProgressView()
                            .frame(width: 54, height: 54))
                    case .success(let image):
                        AnyView(image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 54, height: 54)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(BrockbusterTheme.brockGold, lineWidth: 2)))
                    case .failure:
                        AnyView(Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 54, height: 54)
                            .foregroundColor(BrockbusterTheme.brockGold))
                    @unknown default:
                        AnyView(EmptyView())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if let user = session.currentUser {
                    Text("Welcome, \(user.name)")
                        .font(BrockbusterTheme.Fonts.title)
                        .foregroundColor(colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)
                }
                Text(model.slogan)
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(
                        (colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)
                            .opacity(0.82)
                    )
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
                    .foregroundColor(colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)
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

    @Published var isLoadingResume: Bool = false
    @Published var isLoadingRecentMovies: Bool = false
    @Published var isLoadingRecentShows: Bool = false

    private var hasBootstrapped = false

    func bootstrapIfNeeded(session: SessionStore) async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        slogan = Self.randomSlogan()

        preloadProgress = 0.08
        if session.isLoggedIn && session.libraries.isEmpty {
            do { try await session.fetchLibraries() } catch { }
        }
        preloadProgress = 0.34

        // Allow the user to begin interacting as soon as we have the basics.
        // Remaining sections will fill in progressively with animations.
        withAnimation(.easeInOut(duration: 0.25)) {
            isPreloading = false
        }

        let libs = session.libraries
        let movieLib = libs.first(where: { $0.name.lowercased().contains("movie") })
        let tvLib = libs.first(where: { $0.name.lowercased().contains("tv") || $0.name.lowercased().contains("show") })

        // Load sections lazily. They animate in as each request completes.
        Task { [weak self] in
            await self?.loadResume(session: session)
        }

        Task { [weak self] in
            await self?.loadRecentMovies(session: session, movieLibId: movieLib?.id)
        }

        Task { [weak self] in
            await self?.loadRecentShows(session: session, tvLibId: tvLib?.id)
        }

        preloadProgress = 1.0
    }

    @MainActor
    private func loadResume(session: SessionStore) async {
        isLoadingResume = true
        do {
            let items = try await session.fetchResumeItems(limit: 18)
            withAnimation(.easeOut(duration: 0.25)) {
                resumeItems = items
            }
        } catch {
            resumeItems = []
        }
        isLoadingResume = false
    }

    @MainActor
    private func loadRecentMovies(session: SessionStore, movieLibId: String?) async {
        guard let movieLibId else { return }
        isLoadingRecentMovies = true
        do {
            let items = try await session.fetchItemsPage(
                parentId: movieLibId,
                includeItemTypes: ["Movie"],
                sortBy: ["DateCreated"],
                sortOrder: "Descending",
                limit: 20,
                recursive: true
            )
            withAnimation(.easeOut(duration: 0.25)) {
                recentMovies = items
            }
        } catch {
            recentMovies = []
        }
        isLoadingRecentMovies = false
    }

    @MainActor
    private func loadRecentShows(session: SessionStore, tvLibId: String?) async {
        guard let tvLibId else { return }
        isLoadingRecentShows = true
        do {
            let items = try await session.fetchItemsPage(
                parentId: tvLibId,
                includeItemTypes: ["Series"],
                sortBy: ["DateCreated"],
                sortOrder: "Descending",
                limit: 20,
                recursive: true
            )
            withAnimation(.easeOut(duration: 0.25)) {
                recentShows = items
            }
        } catch {
            recentShows = []
        }
        isLoadingRecentShows = false
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

private enum SectionStyle { case plain, card }

private struct LibraryChip: View {
    let title: String
    let imageURL: URL?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.10))
                if let imageURL {
                    BBCachedAsyncImage(url: imageURL, targetSize: CGSize(width: 260, height: 180)) { phase in
                        switch phase {
                        case .empty:
                            AnyView(ProgressView().tint(BrockbusterTheme.brockGold))
                        case .success(let image):
                            AnyView(image
                                .resizable()
                                .scaledToFill())
                        case .failure:
                            AnyView(Image(systemName: "film")
                                .foregroundColor(.white.opacity(0.65)))
                        @unknown default:
                            AnyView(EmptyView())
                        }
                    }
                } else {
                    Image(systemName: "film")
                        .foregroundColor(.white.opacity(0.65))
                }
            }
            #if os(tvOS)
            .frame(width: 84, height: 58)
            #else
            .frame(width: 54, height: 38)
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                #if os(tvOS)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                #else
                .font(BrockbusterTheme.Fonts.body.weight(.semibold))
                #endif
                .foregroundColor(colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)
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
        #if os(tvOS)
        .focusable(true)
        #endif
    }
}

private struct HomeSection<Content: View>: View {
    let title: String
    var style: SectionStyle = .plain
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BrockbusterTheme.Fonts.title)
                .foregroundColor(colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)

            content()
        }
        .padding(.top, 6)
        .modifier(SectionSurface(style: style))
    }
}

private struct SectionSurface: ViewModifier {
    let style: SectionStyle
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .plain:
            content
        case .card:
            content
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(colorScheme == .dark ? .white.opacity(0.07) : .white.opacity(0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            colorScheme == .dark ? .white.opacity(0.10) : BrockbusterTheme.brockBlue.opacity(0.20),
                            lineWidth: 1
                        )
                )
        }
    }
}

/// Lightweight skeleton rail shown while a home section is loading.
private struct HomeRailPlaceholder: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.colorScheme) private var colorScheme

    private var cardSize: (w: CGFloat, h: CGFloat) {
        #if os(tvOS)
        return (w: 220, h: 330)
        #else
        if hSize == .regular {
            return (w: 180, h: 260)
        }
        return (w: 140, h: 200)
        #endif
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<8, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06))
                        .frame(width: cardSize.w, height: cardSize.h)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(BrockbusterTheme.brockBlue.opacity(0.18), lineWidth: 1)
                        )
                        .redacted(reason: .placeholder)
                }
            }
            .padding(.vertical, 2)
            #if os(tvOS)
            .padding(.vertical, 8)
            #endif
        }
    }
}

private struct HomeRail<Destination: View>: View {
    @EnvironmentObject private var session: SessionStore
    let items: [JellyfinClient.LibraryItem]
    @ViewBuilder let destination: (JellyfinClient.LibraryItem) -> Destination

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink(destination: destination(item)) {
                        HomePosterCard(item: item)
                        #if os(tvOS)
                        .bbTVFocusCard(cornerRadius: 22)
                        #endif
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
            #if os(tvOS)
            .focusSection()
            .padding(.vertical, 8)
            #endif
        }
    }
}

private struct HomePosterCard: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.horizontalSizeClass) private var hSize
    let item: JellyfinClient.LibraryItem

    private var cardSize: (w: CGFloat, h: CGFloat) {
        #if os(tvOS)
        // tvOS needs larger targets for comfortable focus navigation.
        return (w: 220, h: 330)
        #else
        if hSize == .regular {
            return (w: 180, h: 260)
        }
        return (w: 140, h: 200)
        #endif
    }

    private var isEpisode: Bool {
        (item.type ?? "").lowercased() == "episode"
    }

    private var displaySeriesTitle: String {
        item.seriesName?.isEmpty == false ? (item.seriesName ?? item.name) : item.name
    }

    private var episodeDescriptor: String? {
        guard isEpisode else { return nil }
        var parts: [String] = []
        if let s = item.parentIndexNumber, s > 0 { parts.append("Season \(s)") }
        if let e = item.indexNumber, e > 0 { parts.append("Episode \(e)") }
        let joined = parts.joined(separator: " • ")
        return joined.isEmpty ? nil : joined
    }

    private var resumeLabelVisible: Bool {
        if let ud = item.userData,
           let pos = ud.playbackPositionTicks,
           pos > 0,
           (ud.played ?? false) == false {
            return true
        }
        return false
    }

    private var continueWatchingImageURL: URL? {
        guard isEpisode else { return session.itemImageURL(for: item, maxWidth: 420) }

        // Episodes: prefer Season Primary artwork, then Series Primary, then episode Primary.
        if let seasonId = item.seasonId, !seasonId.isEmpty {
            return session.itemImageURL(itemId: seasonId, kind: "Primary", maxWidth: 420)
                ?? session.itemImageURL(for: item, maxWidth: 420)
        }
        if let seriesId = item.seriesId, !seriesId.isEmpty {
            return session.itemImageURL(itemId: seriesId, kind: "Primary", maxWidth: 420)
                ?? session.itemImageURL(for: item, maxWidth: 420)
        }
        return session.itemImageURL(for: item, maxWidth: 420)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                if let url = continueWatchingImageURL {
                    BBCachedAsyncImage(
                        url: url,
                        targetSize: CGSize(width: cardSize.w * 2.0, height: cardSize.h * 2.0)
                    ) { phase in
                        switch phase {
                        case .empty:
                            AnyView(Rectangle().fill(.white.opacity(0.08)))
                        case .success(let image):
                            AnyView(image.resizable().scaledToFill())
                        case .failure:
                            AnyView(Rectangle()
                                .fill(.white.opacity(0.08))
                                .overlay(Image(systemName: "film").foregroundColor(.white.opacity(0.55))))
                        @unknown default:
                            AnyView(Rectangle().fill(.white.opacity(0.08)))
                        }
                    }
                } else {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .overlay(Image(systemName: "film").foregroundColor(.white.opacity(0.55)))
                }

                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.78)]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Text overlay
                VStack(alignment: .leading, spacing: 2) {
                    if isEpisode {
                        Text(displaySeriesTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if let descriptor = episodeDescriptor {
                            Text(descriptor)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.90))
                                .lineLimit(1)
                        }

                        Text(item.name)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(2)
                    } else {
                        Text(item.name)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    if resumeLabelVisible {
                        Text("Resume")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(BrockbusterTheme.brockGold)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.001))
            }
            .frame(width: cardSize.w, height: cardSize.h)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            #if os(tvOS)
            .focusable(true)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BrockbusterTheme.brockGold.opacity(0.22), lineWidth: 2)
            )
            #endif
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
                    BBCachedAsyncImage(url: url, targetSize: CGSize(width: 172, height: 172)) { phase in
                        switch phase {
                        case .empty:
                            AnyView(Circle()
                                .fill(.white.opacity(0.12))
                                .frame(width: 86, height: 86)
                                .overlay(ProgressView().tint(BrockbusterTheme.brockGold)))
                        case .success(let image):
                            AnyView(image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 86, height: 86)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(BrockbusterTheme.brockGold, lineWidth: 3)))
                        case .failure:
                            AnyView(Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 86, height: 86)
                                .foregroundColor(BrockbusterTheme.brockGold))
                        @unknown default:
                            AnyView(EmptyView())
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

