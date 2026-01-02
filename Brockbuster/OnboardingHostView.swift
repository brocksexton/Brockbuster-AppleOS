import SwiftUI

/// Presents the Brockbuster welcome tour on the very first launch (or whenever the
/// user resets it from Settings) and then reveals the provided app content.
///
/// The tour is intentionally self-contained and platform-safe (iOS/iPadOS/tvOS/macOS)
/// so it cannot break builds for secondary targets.
struct OnboardingHostView<Content: View>: View {
    @AppStorage("onboarding.didComplete") private var didCompleteOnboarding: Bool = false
    @AppStorage("onboarding.preferSkip") private var preferSkip: Bool = false

    @ViewBuilder var content: () -> Content

    @State private var showTour: Bool = false

    var body: some View {
        content()
            .onAppear {
                // Defer the presentation so we never fight SwiftUI's initial layout.
                if didCompleteOnboarding == false && preferSkip == false {
                    DispatchQueue.main.async {
                        showTour = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showTour) {
                WelcomeTourView {
                    didCompleteOnboarding = true
                    showTour = false
                } onSkipForever: {
                    // If someone skips, we still mark onboarding as complete so it
                    // doesn't block the experience on next launch.
                    preferSkip = true
                    didCompleteOnboarding = true
                    showTour = false
                }
                // Avoid accidental dismiss without an explicit action.
                .interactiveDismissDisabled(true)
            }
    }
}
