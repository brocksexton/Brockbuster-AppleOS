import SwiftUI
import AVKit

struct NowPlayingBar: View {
    @EnvironmentObject private var nowPlaying: NowPlayingManager

    var body: some View {
        if let item = nowPlaying.item {
            Button {
                nowPlaying.presentPlayer()
            } label: {
                HStack(spacing: 12) {
                    poster(item)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrockbusterTheme.textPrimary)
                            .lineLimit(1)

                        if let sub = item.subtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.caption)
                                .foregroundStyle(BrockbusterTheme.textSecondary)
                                .lineLimit(1)
                        }

                        ProgressView(value: nowPlaying.progress)
                            .progressViewStyle(.linear)
                            .tint(BrockbusterTheme.ticketYellow)
                    }

                    Spacer(minLength: 0)

                    Button {
                        nowPlaying.togglePlayPause()
                    } label: {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrockbusterTheme.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        nowPlaying.stop(playedToCompletion: false, failed: false)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(BrockbusterTheme.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func poster(_ item: NowPlayingManager.NowPlayingItem) -> some View {
        if let url = item.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            placeholder
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.10))
            Image(systemName: "film.fill")
                .foregroundStyle(BrockbusterTheme.ticketYellow)
        }
    }
}
