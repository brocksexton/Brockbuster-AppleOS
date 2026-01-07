import SwiftUI

/// Player "Cast" affordance.
///
/// Today this is implemented as the system route picker (AirPlay / audio-video routes).
///
/// Roadmap:
/// - Add Google Cast (Chromecast / Android TV) behind a feature flag and only on iOS/iPadOS.
/// - Add Roku discovery + launch (SSDP + ECP) as a separate integration.
/// - If the target is an Apple TV running Brockbuster, switch to an enhanced control channel.
struct CastButton: View {
    var size: CGFloat = 40

    var body: some View {
        #if os(tvOS)
        // tvOS does not expose the same system route picker affordance.
        EmptyView()
        #else
        ZStack {
            // Ensure it visually matches the rest of the top bar controls.
            Circle()
                .fill(Color.black.opacity(0.50))
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))

            // Use AVRoutePickerView so the system presents supported routes.
            // This draws its own glyph.
            CastRoutePickerView()
                .frame(width: size, height: size)
                .accessibilityLabel("Cast")
                .accessibilityHint("Choose a device to play on")
        }
        .frame(width: size, height: size)
        #endif
    }
}
