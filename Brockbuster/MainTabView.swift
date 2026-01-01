import SwiftUI
import UIKit

/// The top-level view displayed after the user logs in.  It presents a tabbed interface
/// with placeholders for upcoming features (Friends, Server Health, Social) and the
/// existing Home tab that shows the user's media libraries.  Each tab is wrapped in
/// its own navigation view to allow for deep navigation (e.g. library detail views).
struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var nowPlaying: NowPlayingManager

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }

            NavigationStack {
                MyBrockbusterView()
            }
            .tabItem {
                Image(systemName: "sparkles")
                Text("My")
            }

            NavigationStack {
                ServerHealthTab()
            }
            .tabItem {
                Image(systemName: "waveform.path.ecg")
                Text("Health")
            }

            NavigationStack {
                MoreView()
            }
            .tabItem {
                Image(systemName: "ellipsis.circle")
                Text("More")
            }
            }

            // Now Playing bar
            NowPlayingBar()
                .environmentObject(nowPlaying)
        }
        .tint(BrockbusterTheme.brockGold)
        // NOTE: `nowPlaying` is an `@EnvironmentObject`, so `$nowPlaying` yields an
        // `EnvironmentObject.Wrapper`, not a binding to `@Published` properties.
        // Create an explicit binding instead.
        .fullScreenCover(
            isPresented: Binding(
                get: { nowPlaying.isPlayerPresented },
                set: { nowPlaying.isPlayerPresented = $0 }
            )
        ) {
            NowPlayingFullscreenView()
                .environmentObject(nowPlaying)
        }

        .onAppear {
            // Customize tab bar appearance on iOS to improve contrast for unselected items
            #if os(iOS)
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(BrockbusterTheme.brockDark)
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(BrockbusterTheme.brockGold)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(BrockbusterTheme.brockGold)]
            // Light colour for unselected icons and labels
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor(BrockbusterTheme.brockLight).withAlphaComponent(0.7)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(BrockbusterTheme.brockLight).withAlphaComponent(0.7)]
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
            #endif
        }
    }
}

/// Placeholder view for the Friends tab.  This will eventually show a list of
/// friends and their profiles from the secondary project.  For now it displays a
/// message indicating the feature is under construction.
struct FriendsTab: View {
    var body: some View {
        ZStack {
            // Slightly lighter gradient for improved contrast
            LinearGradient(gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.6), BrockbusterTheme.brockBlue.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "person.2.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(BrockbusterTheme.brockGold)
                Text("Friends List Coming Soon")
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)
                Text("Connect with your friends and see what they're watching.")
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Friends")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
    }
}

/// information about the Jellyfin server such as CPU usage, memory and active
/// streams.
struct ServerHealthTab: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    @StateObject private var vm = ServerHealthViewModel()

    private var columns: [GridItem] {
        // Responsive: 1 column compact, 2 columns on larger screens
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    BrockbusterTheme.brockDark.opacity(0.6),
                    BrockbusterTheme.brockBlue.opacity(0.6)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header

                    if let error = vm.errorMessage {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Unable to load server health", systemImage: "exclamationmark.triangle.fill")
                                    .font(BrockbusterTheme.Fonts.title)
                                    .foregroundColor(BrockbusterTheme.brockGold)

                                Text(error)
                                    .font(BrockbusterTheme.Fonts.body)
                                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.9))
                            }
                        }
                    }

                    if vm.isLoading {
                        GlassCard {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Loading health data…")
                                    .font(BrockbusterTheme.Fonts.body)
                                    .foregroundColor(BrockbusterTheme.brockLight)
                            }
                        }
                    }

                    if let health = vm.health, health.ok {
                        badgesSection(health)
                        checksSection(health)
                        storageSection(health)
                        environmentSection(health)
                        loadSection(health)
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .refreshable {
                await vm.refresh(
                    jellyfinToken: session.accessToken,
                    jellyfinUserId: session.currentUser?.id
                )
            }
        }
        .navigationTitle("Server Health")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await vm.refresh(
                            jellyfinToken: session.accessToken,
                            jellyfinUserId: session.currentUser?.id
                        )
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh server health")
            }
        }
        .task {
            await vm.refresh(
                jellyfinToken: session.accessToken,
                jellyfinUserId: session.currentUser?.id
            )
        }
    }

    private var header: some View {
        GlassCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(BrockbusterTheme.brockGold)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Brockbuster Server")
                        .font(BrockbusterTheme.Fonts.title)
                        .foregroundColor(BrockbusterTheme.brockLight)

                    let last = BrockbusterFormat.isoToDisplay(vm.health?.generatedAt)
                    Text("Last updated: \(last)")
                        .font(.caption)
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                }

                Spacer()
            }
        }
    }

    private func badgesSection(_ health: BrockbusterAPI.HealthV2Response) -> some View {
        let badges = health.status?.badges ?? []

        return Group {
            if !badges.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Status")
                            .font(BrockbusterTheme.Fonts.title)
                            .foregroundColor(BrockbusterTheme.brockLight)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(badges) { badge in
                                HStack(spacing: 10) {
                                    let sev = HealthSeverity(badge.type)
                                    SeverityPill(severity: sev)
                                    Text(badge.label ?? "—")
                                        .font(BrockbusterTheme.Fonts.body)
                                        .foregroundColor(BrockbusterTheme.brockLight)
                                    Spacer()
                                }
                            }
                        }

                        if let banner = health.status?.banner, !banner.isEmpty {
                            Text(banner)
                                .font(.caption)
                                .foregroundColor(BrockbusterTheme.brockGold)
                                .padding(.top, 6)
                        }
                    }
                }
            }
        }
    }

    private func checksSection(_ health: BrockbusterAPI.HealthV2Response) -> some View {
        GlassCard {
            HStack {
                Text("Jellyfin API")
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)

                Spacer()

                let ok = health.checks?.jellyfinPublicInfoOk ?? false
                Label(ok ? "OK" : "Down", systemImage: ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(ok ? BrockbusterTheme.brockGold : BrockbusterTheme.brockLight.opacity(0.85))
            }
        }
    }

    private func storageSection(_ health: BrockbusterAPI.HealthV2Response) -> some View {
        let drives = health.storage?.drives ?? []

        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Storage")
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)

                if drives.isEmpty {
                    Text("No drives reported by API.")
                        .font(BrockbusterTheme.Fonts.body)
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.85))
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(drives) { d in
                            driveCard(d)
                        }
                    }
                }

                if let t = health.storage?.thresholds {
                    let warn = t.warningFreePercent ?? 20
                    let crit = t.criticalFreePercent ?? 10
                    Text("Thresholds: Critical ≤ \(String(format: "%.0f", crit))% free • Warning ≤ \(String(format: "%.0f", warn))% free")
                        .font(.caption)
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.7))
                        .padding(.top, 6)
                }
            }
        }
    }

    private func driveCard(_ d: BrockbusterAPI.HealthV2Response.StorageBlock.Drive) -> some View {
        let sev = HealthSeverity(d.severity)
        let used = BrockbusterFormat.bytes(d.usedBytes)
        let free = BrockbusterFormat.bytes(d.freeBytes)
        let total = BrockbusterFormat.bytes(d.totalBytes)
        let freePct = d.freePercent.map { String(format: "%.1f%% free", $0) } ?? "—"

        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.label ?? (d.mount ?? "Drive"))
                            .font(BrockbusterTheme.Fonts.body)
                            .foregroundColor(BrockbusterTheme.brockLight)
                            .lineLimit(2)

                        Text("\(used) used • \(free) free • \(total) total")
                            .font(.caption)
                            .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                            .lineLimit(1)

                        Text(freePct)
                            .font(.caption)
                            .foregroundColor(BrockbusterTheme.brockLight.opacity(0.75))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        SeverityPill(severity: sev)
                        RolePill(role: d.role)
                    }
                }

                UsageBar(fraction: d.usedFraction)
            }
        }
    }

    private func environmentSection(_ health: BrockbusterAPI.HealthV2Response) -> some View {
        // A3 v2 payload may not include env; show only if caller info exists as a placeholder
        // If you add env later, wire it here. For now show caller as “Authenticated as”.
        return Group {
            if let caller = health.caller, (caller.userId != nil || caller.name != nil) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session")
                            .font(BrockbusterTheme.Fonts.title)
                            .foregroundColor(BrockbusterTheme.brockLight)

                        Text("Authenticated as: \(caller.name ?? "User")")
                            .font(BrockbusterTheme.Fonts.body)
                            .foregroundColor(BrockbusterTheme.brockLight)

                        if let id = caller.userId, !id.isEmpty {
                            Text("User ID: \(id)")
                                .font(.caption)
                                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                        }
                    }
                }
            }
        }
    }

    private func loadSection(_ health: BrockbusterAPI.HealthV2Response) -> some View {
        // A3 v2 sample doesn’t include load, so we skip unless you add it later.
        // If you do add it to v2, wire it similarly to your prior view.
        EmptyView()
    }
}


/// Placeholder view for the Social tab.  This tab will eventually allow users to
/// share reviews and thoughts about media with friends and family.  Currently it
/// displays a friendly placeholder message.
struct SocialTab: View {
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.6), BrockbusterTheme.brockBlue.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "quote.bubble.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(BrockbusterTheme.brockGold)
                Text("Social Feed Coming Soon")
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)
                Text("Share your thoughts on movies and shows with friends.")
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Social")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
    }
}

#if DEBUG
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(SessionStore())
    }
}
#endif

