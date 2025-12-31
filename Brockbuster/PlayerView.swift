import SwiftUI
import AVKit

/// A simple full‑screen video player that streams content from a given URL.
/// The player is created with an `AVPlayer` and presented within a SwiftUI
/// `VideoPlayer`.  When the view appears the video begins playing
/// automatically.  A dismiss button is provided to close the player.
struct PlayerView: View {
    /// The URL of the media to play.  Must be a valid HTTP/HTTPS resource
    /// provided by the Jellyfin server's streaming endpoint.
    let url: URL
    /// Environment property to dismiss the view when presented as a sheet.
    @Environment(\.dismiss) private var dismiss
    /// The underlying AVPlayer.  Stored as a StateObject so it persists
    /// across view updates.
    @StateObject private var player = AVPlayerWrapper()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Video content
            VideoPlayer(player: player.player)
                .onAppear {
                    // Assign the media URL to the player when the view appears
                    player.player.replaceCurrentItem(with: AVPlayerItem(url: url))
                    player.player.play()
                }
                .ignoresSafeArea()
            // Dismiss button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
                    .padding()
            }
        }
        .background(Color.black)
    }
}

/// A wrapper class for AVPlayer to enable use with `@StateObject`.  Without
/// wrapping the player in a class conforming to `ObservableObject`, SwiftUI
/// would recreate the player whenever the view updates, interrupting
/// playback.  By storing the player here the instance persists until the
/// view is destroyed.
final class AVPlayerWrapper: ObservableObject {
    let player: AVPlayer
    init() {
        self.player = AVPlayer()
    }
}

#if DEBUG
struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        // Use a sample URL for preview; this won't actually play in Xcode
        PlayerView(url: URL(string: "https://example.com/video.mp4")!)
    }
}
#endif