import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@main
struct BrockbusterApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var accountManager = AccountManager()
    @StateObject private var nowPlaying = NowPlayingManager()
    @StateObject private var downloads = DownloadManager()
    @StateObject private var castManager = CastManager()
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
            OnboardingHostView {
                contentView()
            }
                .environmentObject(session)
                .environmentObject(accountManager)
                .environmentObject(nowPlaying)
                .environmentObject(downloads)
                .environmentObject(castManager)
                .bbEnableBugReportShake(session: session)
        }
    }

    /// Root view builder which returns the appropriate view based on session state.
    @ViewBuilder
    private func contentView() -> some View {
        if !session.isLoggedIn {
            // If there are remembered accounts, let the user choose one to continue,
            // or add another account.  Remembered accounts carry their own server URL.
            if accountManager.hasRememberedAccounts {
                if showAccountChooserOnLaunch {
                    AccountChooserView()
                } else {
                    AutoSignInView()
                }
            } else if !session.hasConfiguredServer {
                // No server known yet (fresh install without a bundled default):
                // ask for the Jellyfin server address before showing login.
                ServerSetupView()
            } else {
                // No remembered accounts: show the standard login.
                LoginView()
            }
        } else {
            // Logged in: if Brockbuster is unreachable (or we have entered sticky
            // offline mode), default to offline-first UI.
            if session.connectionState == .offline || session.offlineModeEnabled {
                OfflineServerView()
            } else {
                // Online (or unknown while we check): show the main tabbed interface.
                MainTabView()
            }
        }
    }
}

// MARK: - Shake to Report Bug (iPhone only)

private extension Notification.Name {
    static let bbDeviceDidShake = Notification.Name("bbDeviceDidShake")
}

#if canImport(UIKit) && !os(tvOS)
private extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        NotificationCenter.default.post(name: .bbDeviceDidShake, object: nil)
    }
}

private struct BugReportShakePresenter: ViewModifier {
    @ObservedObject var session: SessionStore

    @State private var confirmShakeReport: Bool = false
    @State private var presentBugReport: Bool = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .bbDeviceDidShake)) { _ in
                guard UIDevice.current.userInterfaceIdiom == .phone else { return }
                confirmShakeReport = true
            }
            .alert("Report a bug?", isPresented: $confirmShakeReport) {
                Button("Cancel", role: .cancel) {}
                Button("Report") {
                    presentBugReport = true
                }
            } message: {
                Text("Shake detected. Would you like to send a bug report?")
            }
            .sheet(isPresented: $presentBugReport) {
                NavigationStack {
                    BugReportView(entryPoint: .shake)
                        .environmentObject(session)
                }
            }
    }
}
#endif

extension View {
    /// Enables the iPhone-only shake gesture to trigger a "Report a Bug" prompt.
    /// Inert unless a bug-report webhook is configured in AppConfig.
    @ViewBuilder
    func bbEnableBugReportShake(session: SessionStore) -> some View {
        #if canImport(UIKit) && !os(tvOS)
        if AppConfig.bugReportingEnabled {
            self.modifier(BugReportShakePresenter(session: session))
        } else {
            self
        }
        #else
        self
        #endif
    }
}
