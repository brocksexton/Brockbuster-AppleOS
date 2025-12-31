import SwiftUI

@main
struct BrockbusterApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            // Top-level navigation is controlled by the session's login state
            contentView()
                .environmentObject(session)
        }
    }

    /// Root view builder which returns the appropriate view based on session state.
    @ViewBuilder
    private func contentView() -> some View {
        if !session.isLoggedIn {
            // When not logged in we always present the login screen.  We no longer need
            // to explicitly ask for server URL since a default is assumed.  Users can
            // change the server from the login screen via the "Change Server" button.
            LoginView()
        } else {
            // Logged in: show the tabbed interface with home and placeholders for
            // friends, server health and social feed.
            MainTabView()
        }
    }
}
