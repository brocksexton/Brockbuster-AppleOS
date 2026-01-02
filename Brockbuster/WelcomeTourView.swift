import SwiftUI

/// A polished first-launch tour that introduces Brockbuster's core areas.
///
/// The tour is a simple multi-page experience (no fragile UI introspection)
/// so it remains reliable across iOS/iPadOS/tvOS/macOS builds.
struct WelcomeTourView: View {
    struct Page: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let systemImage: String
    }

    private let pages: [Page] = [
        Page(
            title: "Welcome to Brockbuster",
            subtitle: "Your premium, cinema-first Jellyfin experience — tuned for Apple platforms.",
            systemImage: "film.stack"
        ),
        Page(
            title: "Home",
            subtitle: "Browse your libraries fast, pick up where you left off, and jump into Recently Added.",
            systemImage: "house.fill"
        ),
        Page(
            title: "My Brockbuster",
            subtitle: "Keep your favourites, watch history, and personal picks in one place.",
            systemImage: "sparkles"
        ),
        Page(
            title: "Now Playing",
            subtitle: "A mini-player keeps your session accessible — and the fullscreen player supports a more modern experience.",
            systemImage: "play.rectangle.fill"
        ),
        Page(
            title: "Health & More",
            subtitle: "Check server health, manage accounts, and find settings without cluttering your main navigation.",
            systemImage: "waveform.path.ecg"
        )
    ]

    let onDone: () -> Void
    let onSkipForever: () -> Void

    @State private var selection: Int = 0

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    BrockbusterTheme.brockDark,
                    BrockbusterTheme.brockBlue.opacity(0.8)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                header

                TabView(selection: $selection) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, page in
                        pageView(page)
                            .tag(idx)
                            .padding(.horizontal, 18)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .always))
                #elseif os(tvOS)
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                #endif

                controls
            }
            .padding(.vertical, 22)
        }
    }

    private var header: some View {
        HStack {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            Spacer()

            Button {
                onSkipForever()
            } label: {
                Text("Skip")
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.9))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
    }

    private func pageView(_ page: Page) -> some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(radius: 12)

                VStack(spacing: 14) {
                    Image(systemName: page.systemImage)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundColor(BrockbusterTheme.brockGold)

                    Text(page.title)
                        .font(BrockbusterTheme.Fonts.title)
                        .foregroundColor(BrockbusterTheme.brockLight)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)

                    Text(page.subtitle)
                        .font(BrockbusterTheme.Fonts.body)
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
                .padding(18)
            }
            .frame(maxWidth: 640)

            if selection == 0 {
                Text("Tip: You can re-open this tour anytime from More → Settings.")
                    .font(.footnote)
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selection = max(0, selection - 1)
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .tint(Color.white.opacity(0.20))
            .foregroundColor(BrockbusterTheme.brockLight)
            .disabled(selection == 0)

            Spacer()

            if selection < pages.count - 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = min(pages.count - 1, selection + 1)
                    }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(BrockbusterTheme.brockGold)
            } else {
                Button {
                    onDone()
                } label: {
                    Text("Get Started")
                        .font(BrockbusterTheme.Fonts.title)
                }
                .buttonStyle(.borderedProminent)
                .tint(BrockbusterTheme.brockGold)
            }
        }
        .padding(.horizontal, 18)
    }
}

#if DEBUG
struct WelcomeTourView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeTourView {
        } onSkipForever: {
        }
    }
}
#endif
