import SwiftUI
import AVKit

struct NowPlayingBar: View {
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    @EnvironmentObject private var session: SessionStore

    @State private var isFavorite: Bool? = nil
    @State private var isTogglingFavorite: Bool = false

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
                        Task { await toggleFavorite(for: item.id) }
                    } label: {
                        Image(systemName: (isFavorite ?? false) ? "heart.fill" : "heart")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle((isFavorite ?? false) ? BrockbusterTheme.ticketYellow : BrockbusterTheme.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                if isTogglingFavorite {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isTogglingFavorite)

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
            .task(id: item.id) {
                await loadFavorite(for: item.id)
            }
        }
    }

    @ViewBuilder
    private func poster(_ item: NowPlayingManager.NowPlayingItem) -> some View {
        if let url = item.posterURL {
            BBCachedAsyncImage(url: url, targetSize: CGSize(width: 88, height: 88)) { phase in
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

    // MARK: - Favorites

    @MainActor
    private func loadFavorite(for itemId: String) async {
        isFavorite = nil
        do {
            let detail = try await session.fetchItemDetails(itemId: itemId)
            isFavorite = detail.userData?.isFavorite ?? false
        } catch {
            isFavorite = false
        }
    }

    @MainActor
    private func toggleFavorite(for itemId: String) async {
        guard session.currentUser != nil else { return }
        let newValue = !(isFavorite ?? false)
        isTogglingFavorite = true
        isFavorite = newValue
        do {
            try await session.setFavorite(itemId: itemId, isFavorite: newValue)
        } catch {
            // Roll back on failure.
            isFavorite?.toggle()
        }
        isTogglingFavorite = false
    }
}
