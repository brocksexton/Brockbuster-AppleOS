import SwiftUI

/// Presents the Brockbuster welcome tour on first launch (and when explicitly
/// requested from Settings) before revealing the provided app content.
///
/// Why this host exists:
/// - It is entirely SwiftUI (no UIKit introspection), so it remains safe for
///   iPadOS/tvOS/macOS targets.
/// - It uses simple persisted flags so onboarding is reliable across launches.
struct OnboardingHostView<Content: View>: View {
    /// Set to true once the user completes or permanently skips the tour.
    @AppStorage("onboarding.didComplete") private var didCompleteOnboarding: Bool = false
    /// A user intent flag if they chose "Skip".
    @AppStorage("onboarding.preferSkip") private var preferSkipOnboarding: Bool = false

    /// Tracks whether the app has ever been launched on this install.
    @AppStorage("onboarding.launchCount") private var launchCount: Int = 0
    /// Allows Settings to request the tour on the next app launch.
    @AppStorage("onboarding.forceShowNextLaunch") private var forceShowNextLaunch: Bool = false

    /// Allows any screen (including pre-login) to request the tour immediately.
    /// This is intentionally AppStorage-backed so it can be triggered from
    /// login/server setup screens that are not yet within the post-login
    /// navigation hierarchy.
    @AppStorage("onboarding.presentNow") private var presentNow: Bool = false

    /// Versioning for onboarding. If the tour experience changes meaningfully,
    /// bump `currentSchema` so existing installs see the updated tour once.
    @AppStorage("onboarding.schemaVersion") private var schemaVersion: Int = 0
    private let currentSchema: Int = 2

    private let content: () -> Content

    @State private var showTour: Bool = false
    @State private var didCheck: Bool = false

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            content()

            if showTour {
                WelcomeTourView {
                    didCompleteOnboarding = true
                    showTour = false
                } onSkipForever: {
                    preferSkipOnboarding = true
                    didCompleteOnboarding = true
                    showTour = false
                }
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .task {
            // Ensure we only evaluate once per appearance.
            guard didCheck == false else { return }
            didCheck = true

            // Show if:
            // - explicitly requested to present right now
            // - requested for next launch
            // - first launch of this install and user didn't skip
            let shouldShow = presentNow
                || forceShowNextLaunch
                || ((schemaVersion < currentSchema) && preferSkipOnboarding == false)
                || (launchCount == 0 && didCompleteOnboarding == false && preferSkipOnboarding == false)

            // Record that we've launched.
            launchCount += 1
            forceShowNextLaunch = false
            presentNow = false

            if shouldShow {
                schemaVersion = currentSchema
            }

            if shouldShow {
                // Defer one tick so initial view tree settles.
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showTour = true
                    }
                }
            }
        }
    }
}
