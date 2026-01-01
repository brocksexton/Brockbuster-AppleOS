import SwiftUI

/// Backwards-compatible wrapper kept to avoid build breaks when older
/// references to `FullscreenNowPlayingView` remain in the project.
///
/// The new player surface is `NowPlayingFullscreenView`.
struct FullscreenNowPlayingView: View {
    var body: some View {
        NowPlayingFullscreenView()
    }
}
