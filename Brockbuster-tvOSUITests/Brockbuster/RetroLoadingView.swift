import SwiftUI

/// A full-screen loading view inspired by VHS scanlines and retro video players.
/// Displays animated horizontal bars sliding across the screen and optionally a
/// central logo.  Use this view while performing network requests or heavy
/// operations to give users clear feedback and maintain the app's theme.
struct RetroLoadingView: View {
    /// Whether to show the Brockbuster logo.  By default it is visible.
    var showsLogo: Bool = true
    /// An optional status text shown below the logo.
    var status: String? = nil
    /// Animation state for the moving stripes
    @State private var offset: CGFloat = -1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark background
                BrockbusterTheme.brockDark
                    .ignoresSafeArea()
                // Moving stripes layer with masking to subtly blend into background
                StripesView(offset: offset)
                    .mask(BrockbusterTheme.brockDark.opacity(0.4))
                // Logo and optional status
                if showsLogo {
                    VStack(spacing: 16) {
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 8)
                        if let status = status {
                            Text(status)
                                .font(BrockbusterTheme.Fonts.body)
                                .foregroundColor(BrockbusterTheme.brockLight)
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .onAppear {
                // Animate the offset repeatedly to create the moving stripes effect
                offset = -1.0
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    offset = 1.0
                }
            }
        }
    }

    /// A subview representing the moving stripes.  The stripes are drawn using
    /// SwiftUI rectangles and their horizontal position is animated via the
    /// `offset` binding passed from the parent.  Stripes extend beyond the
    /// screen bounds to avoid visible gaps during animation.
    private struct StripesView: View {
        var offset: CGFloat
        var body: some View {
            GeometryReader { geo in
                let stripeHeight: CGFloat = 6
                let spacing: CGFloat = 12
                let total = Int((geo.size.height + stripeHeight + spacing) / (stripeHeight + spacing))
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(0..<total, id: \.self) { _ in
                        Rectangle()
                            .fill(BrockbusterTheme.brockBlue.opacity(0.3))
                            .frame(height: stripeHeight)
                            .offset(x: offset * geo.size.width)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}
