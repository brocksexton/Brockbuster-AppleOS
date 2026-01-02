import SwiftUI

@main
struct BrockbusterApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var accountManager = AccountManager()
    @StateObject private var nowPlaying = NowPlayingManager()
    @AppStorage("settings.showAccountChooserOnLaunch") private var showAccountChooserOnLaunch: Bool = true

    init() {
        // Provide a reasonably sized shared URL cache so that artwork (posters, backdrops,
        // avatars) doesn't get re-downloaded every time a view reappears.
        //
        // These values are intentionally conservative for mobile devices while still
        // meaningfully improving scroll performance and reducing network churn.
        let memoryCapacity = 60 * 1024 * 1024   // 60 MB
        let diskCapacity = 250 * 1024 * 1024    // 250 MB
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity)
    }

    var body: some Scene {
        WindowGroup {
            // Top-level navigation is controlled by the session's login state
            contentView()
                .environmentObject(session)
                .environmentObject(accountManager)
                .environmentObject(nowPlaying)
        }
    }

    /// Root view builder which returns the appropriate view based on session state.
    @ViewBuilder
    private func contentView() -> some View {
        if !session.isLoggedIn {
            // If there are remembered accounts, let the user choose one to continue,
            // or add another account.
            if accountManager.hasRememberedAccounts {
                if showAccountChooserOnLaunch {
                    AccountChooserView()
                } else {
                    AutoSignInView()
                }
            } else {
                // No remembered accounts: show the standard login.
                LoginView()
            }
        } else {
            // Logged in: show the tabbed interface with home and placeholders for
            // friends, server health and social feed.
            MainTabView()
        }
    }
}
