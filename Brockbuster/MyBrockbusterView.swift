import SwiftUI

/// A utility hub for personal features that don't need to live in the primary
/// navigation yet (watch history, continue watching, favourites, etc.).
///
/// This view is intentionally designed as a "sub menu" tab so it can grow over
/// time without cluttering the main tab bar.
struct MyBrockbusterView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var resumeItems: [JellyfinClient.LibraryItem] = []
    @State private var historyItems: [JellyfinClient.LibraryItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    BrockbusterTheme.brockDark.opacity(0.65),
                    BrockbusterTheme.brockBlue.opacity(0.55)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    header

                    quickActions

                    if !resumeItems.isEmpty {
                        sectionHeader(title: "Continue Watching", subtitle: "Pick up right where you left off") {
                            NavigationLink {
                                ResumeItemsView()
                                    .environmentObject(session)
                            } label: {
                                Text("See all")
                            }
                        }

                        HorizontalPosterRail(items: resumeItems) { item in
                            destination(for: item)
                        }
                    }

                    if !historyItems.isEmpty {
                        sectionHeader(title: "Watch History", subtitle: "Recently played") {
                            NavigationLink {
                                WatchHistoryView()
                                    .environmentObject(session)
                            } label: {
                                Text("See all")
                            }
                        }

                        VStack(spacing: 10) {
                            ForEach(historyItems.prefix(8)) { item in
                                NavigationLink {
                                    destination(for: item)
                                } label: {
                                    HistoryRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if isLoading {
                        loadingCard
                    }

                    if let errorMessage = errorMessage {
                        ErrorPill(text: errorMessage)
                            .padding(.top, 6)
                    }

                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        }
        .navigationTitle("My Brockbuster")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("My Brockbuster")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight)

            Text("Your picks, history, and shortcuts.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))
        }
        .padding(.top, 4)
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                NavigationLink {
                    WatchHistoryView().environmentObject(session)
                } label: {
                    QuickActionCard(
                        icon: "clock.arrow.circlepath",
                        title: "History",
                        subtitle: "What you watched"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ResumeItemsView().environmentObject(session)
                } label: {
                    QuickActionCard(
                        icon: "play.circle.fill",
                        title: "Continue",
                        subtitle: "Resume playback"
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                NavigationLink {
                    ComingSoonView(
                        title: "Favourites",
                        message: "A dedicated favourites list is coming soon. For now, you can favourite items in Jellyfin and we’ll surface them here."
                    )
                } label: {
                    QuickActionCard(
                        icon: "heart.fill",
                        title: "Favourites",
                        subtitle: "Save for later"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ComingSoonView(
                        title: "Downloads",
                        message: "Offline downloads are planned for a future update."
                    )
                } label: {
                    QuickActionCard(
                        icon: "arrow.down.circle.fill",
                        title: "Downloads",
                        subtitle: "Offline later"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(title: String, subtitle: String, trailing: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)
                Text(subtitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor((colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark).opacity(0.72))
            }
            Spacer()
            trailing()
                .font(.footnote.weight(.semibold))
                .foregroundColor(BrockbusterTheme.brockGold)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(BrockbusterTheme.brockGold)
            Text("Refreshing…")
                .font(.footnote.weight(.semibold))
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.85))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func destination(for item: JellyfinClient.LibraryItem) -> AnyView {
        if item.mediaType == "Series" || (item.type ?? "").lowercased() == "series" {
            return AnyView(SeriesDetailView(series: item).environmentObject(session))
        }
        if item.mediaType == "BoxSet" || (item.type ?? "").lowercased() == "boxset" {
            return AnyView(CollectionDetailView(collection: item).environmentObject(session))
        }
        return AnyView(ItemDetailView(item: item).environmentObject(session))
    }

    private func refresh() async {
        guard session.isLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let resume = session.fetchResumeItems(limit: 18)
            async let history = session.fetchWatchHistory(limit: 24)
            let (r, h) = try await (resume, history)
            resumeItems = r
            historyItems = h
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Subviews

private struct QuickActionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(BrockbusterTheme.brockGold.opacity(colorScheme == .dark ? 0.18 : 0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(BrockbusterTheme.brockGold)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor((colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark).opacity(0.70))
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(colorScheme == .dark ? .white.opacity(0.10) : BrockbusterTheme.brockBlue.opacity(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct HorizontalPosterRail: View {
    @EnvironmentObject private var session: SessionStore
    let items: [JellyfinClient.LibraryItem]
    let destination: (JellyfinClient.LibraryItem) -> AnyView

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink {
                        destination(item).environmentObject(session)
                    } label: {
                        PosterCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct PosterCard: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.horizontalSizeClass) private var hSize
    let item: JellyfinClient.LibraryItem

    private var cardSize: (w: CGFloat, h: CGFloat) {
        if hSize == .regular { return (w: 180, h: 260) }
        return (w: 140, h: 200)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
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
            }
            .frame(width: cardSize.w, height: cardSize.h)
            .clipped()

            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.75)]),
                startPoint: .top,
                endPoint: .bottom
            )

            Text(item.name)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(10)
        }
        .frame(width: cardSize.w, height: cardSize.h)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.colorScheme) private var colorScheme
    let item: JellyfinClient.LibraryItem

    private var subtitle: String {
        let isEpisode = (item.type ?? "").lowercased() == "episode"
        if isEpisode {
            var parts: [String] = []
            if let s = item.parentIndexNumber, s > 0 { parts.append("S\(s)") }
            if let e = item.indexNumber, e > 0 { parts.append("E\(e)") }
            let se = parts.joined()
            if let series = item.seriesName, !series.isEmpty {
                if se.isEmpty { return series }
                return "\(series) • \(se)"
            }
            return se.isEmpty ? "Episode" : se
        }
        return item.productionYear.map { String($0) } ?? "Movie"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let url = session.itemImageURL(for: item, maxWidth: 260) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(.white.opacity(0.08))
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Rectangle().fill(.white.opacity(0.08))
                        @unknown default:
                            Rectangle().fill(.white.opacity(0.08))
                        }
                    }
                } else {
                    Rectangle().fill(.white.opacity(0.08))
                }
            }
            .frame(width: 62, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor((colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark).opacity(0.70))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundColor((colorScheme == .dark ? BrockbusterTheme.brockLight : BrockbusterTheme.brockDark).opacity(0.35))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(colorScheme == .dark ? .white.opacity(0.10) : BrockbusterTheme.brockBlue.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct ResumeItemsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var items: [JellyfinClient.LibraryItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.60), BrockbusterTheme.brockBlue.opacity(0.55)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if isLoading {
                        ProgressView().tint(BrockbusterTheme.brockGold)
                            .padding(.top, 12)
                    }
                    if let errorMessage = errorMessage {
                        ErrorPill(text: errorMessage).padding(.top, 8)
                    }

                    ForEach(items) { item in
                        NavigationLink {
                            if (item.type ?? "").lowercased() == "series" {
                                SeriesDetailView(series: item)
                                    .environmentObject(session)
                            } else if (item.type ?? "").lowercased() == "boxset" {
                                CollectionDetailView(collection: item)
                                    .environmentObject(session)
                            } else {
                                ItemDetailView(item: item)
                                    .environmentObject(session)
                            }
                        } label: {
                            HistoryRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .navigationTitle("Continue Watching")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await session.fetchResumeItems(limit: 100)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}

private struct WatchHistoryView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var items: [JellyfinClient.LibraryItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.60), BrockbusterTheme.brockBlue.opacity(0.55)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if isLoading {
                        ProgressView().tint(BrockbusterTheme.brockGold)
                            .padding(.top, 12)
                    }
                    if let errorMessage = errorMessage {
                        ErrorPill(text: errorMessage).padding(.top, 8)
                    }

                    ForEach(items) { item in
                        NavigationLink {
                            if (item.type ?? "").lowercased() == "series" {
                                SeriesDetailView(series: item)
                                    .environmentObject(session)
                            } else if (item.type ?? "").lowercased() == "boxset" {
                                CollectionDetailView(collection: item)
                                    .environmentObject(session)
                            } else {
                                ItemDetailView(item: item)
                                    .environmentObject(session)
                            }
                        } label: {
                            HistoryRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .navigationTitle("Watch History")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await session.fetchWatchHistory(limit: 250)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}

private struct ComingSoonView: View {
    let title: String
    let message: String

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.60), BrockbusterTheme.brockBlue.opacity(0.55)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(BrockbusterTheme.brockGold)

                Text(title)
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)

                Text(message)
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 44)
            .padding(.horizontal, 18)
        }
        .navigationTitle(title)
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
    }
}

private struct ErrorPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundColor(BrockbusterTheme.brockLight)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }
}

