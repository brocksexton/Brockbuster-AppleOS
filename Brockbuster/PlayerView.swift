import SwiftUI
import AVKit

/// Full-screen player backed by `AVPlayerViewController` so we get:
/// - Apple-native playback controls
/// - Subtitles/CC selection (when available)
/// - Picture in Picture
///
/// We add a lightweight Brockbuster overlay (title/poster + close) that hides
/// when the user dismisses controls.
struct PlayerView: View {
    let url: URL
    let title: String
    let subtitle: String?
    let posterURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var showOverlay: Bool = true
    @State private var overlayHideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            PlayerViewControllerRepresentable(url: url)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleOverlay()
                }

            if showOverlay {
                overlay
                    .transition(.opacity)
                    .onAppear { scheduleOverlayAutoHide() }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onDisappear {
            overlayHideTask?.cancel()
        }
    }

    private var overlay: some View {
        HStack(spacing: 12) {
            if let posterURL {
                AsyncImage(url: posterURL) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.25))
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.25))
                            .overlay(Image(systemName: "film").foregroundColor(.white))
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 40, height: 40)
                .clipped()
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(subtitle ?? "Brockbuster")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.75), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private func toggleOverlay() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showOverlay.toggle()
        }
        if showOverlay {
            scheduleOverlayAutoHide()
        } else {
            overlayHideTask?.cancel()
        }
    }

    private func scheduleOverlayAutoHide() {
        overlayHideTask?.cancel()
        overlayHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                showOverlay = false
            }
        }
    }
}

private struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // If URL changes, replace the player item.
        if let current = (uiViewController.player?.currentItem?.asset as? AVURLAsset)?.url,
           current != url {
            uiViewController.player = AVPlayer(url: url)
            uiViewController.player?.play()
        }
    }
}
