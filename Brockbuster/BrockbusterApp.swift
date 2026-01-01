import SwiftUI

@main
struct BrockbusterApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var accountManager = AccountManager()
    @AppStorage("settings.showAccountChooserOnLaunch") private var showAccountChooserOnLaunch: Bool = true

    var body: some Scene {
        WindowGroup {
            // Top-level navigation is controlled by the session's login state
            contentView()
                .environmentObject(session)
                .environmentObject(accountManager)
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
