import SwiftUI

/// Detail surface for an offline downloaded item.
///
/// This view is intentionally self-contained so users can browse metadata,
/// view cached artwork, play offline, and manage (delete) downloads without
/// needing to reconnect to Jellyfin.
struct DownloadedItemDetailView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    @EnvironmentObject private var session: SessionStore

    let recordId: UUID

    @State private var showDeleteConfirm = false

    private var record: DownloadRecord? {
        downloads.records.first(where: { $0.id == recordId })
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    BrockbusterTheme.brockDark.opacity(0.70),
                    BrockbusterTheme.brockBlue.opacity(0.60)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if let record {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header(record)

                        actions(record)

                        if let overview = record.overview, !overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Overview")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(BrockbusterTheme.brockLight)

                                    Text(overview)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(14)
                            }
                        }

                        details(record)

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.85))

                    Text("Download not found")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(BrockbusterTheme.brockLight)

                    Text("This item may have been removed.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.78))
                }
                .padding()
            }
        }
        .navigationTitle("Details")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
    }

    private func header(_ record: DownloadRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            DownloadedPoster(posterURL: downloads.cachedPosterURL(for: record), fallbackRemoteURL: remotePosterURL(for: record))
                .frame(width: 96, height: 144)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BrockbusterTheme.brockBlue.opacity(0.35), lineWidth: 1)
                )
                .shadow(radius: 10)

            VStack(alignment: .leading, spacing: 8) {
                Text(record.itemName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight)
                    .fixedSize(horizontal: false, vertical: true)

                if let sub = subtitle(for: record) {
                    Text(sub)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.80))
                }

                Text(metaLine(for: record))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.65))

                statusPill(for: record)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func actions(_ record: DownloadRecord) -> some View {
        VStack(spacing: 10) {
            Button {
                play(record)
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Play Offline")
                    Spacer()
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockDark)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(BrockbusterTheme.brockGold.opacity(0.92))
                )
            }
            .buttonStyle(.plain)
            .disabled(downloads.localFileURL(for: record) == nil)

            HStack(spacing: 10) {
                Button {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete")
                        Spacer()
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(BrockbusterTheme.brockBlue.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Delete Download?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        downloads.remove(record: record)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove the file from this device.")
                }

                if record.state == .failed {
                    Button {
                        // Retry requires an online session, but calling enqueue will
                        // correctly handle offline failures.
                        downloads.retry(record: record, sessionStore: session)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                            Spacer()
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(BrockbusterTheme.brockLight)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(BrockbusterTheme.brockBlue.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func details(_ record: DownloadRecord) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Details")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight)

                KeyValueRow(label: "Type", value: record.mediaType ?? "Unknown")

                if let year = record.productionYear {
                    KeyValueRow(label: "Year", value: String(year))
                }

                if let ticks = record.runtimeTicks {
                    KeyValueRow(label: "Runtime", value: formatRuntime(ticks))
                }

                if let expected = record.bytesExpected, expected > 0 {
                    KeyValueRow(label: "Size", value: byteString(expected))
                } else if let written = record.bytesWritten, written > 0 {
                    KeyValueRow(label: "Size", value: byteString(written))
                }

                KeyValueRow(label: "Last updated", value: formattedDate(record.updatedAt))
            }
            .padding(14)
        }
    }

    private func play(_ record: DownloadRecord) {
        guard let url = downloads.localFileURL(for: record) else { return }

        let subtitle = subtitle(for: record)
        let posterURL = downloads.cachedPosterURL(for: record) ?? remotePosterURL(for: record)

        let mediaKind: NowPlayingManager.MediaKind = (record.seriesName == nil ? .movie : .episode)

        nowPlaying.playOffline(
            itemId: record.itemId,
            title: record.itemName,
            subtitle: subtitle,
            posterURL: posterURL,
            startPositionTicks: 0,
            mediaKind: mediaKind,
            seriesTitle: record.seriesName,
            seasonNumber: record.seasonNumber,
            episodeNumber: record.episodeNumber,
            episodeTitle: (mediaKind == .episode ? record.itemName : nil),
            localURL: url
        )
    }

    private func subtitle(for record: DownloadRecord) -> String? {
        guard let series = record.seriesName else { return nil }
        if let s = record.seasonNumber, let e = record.episodeNumber {
            return "\(series) • S\(s) E\(e)"
        }
        return series
    }

    private func remotePosterURL(for record: DownloadRecord) -> URL? {
        guard session.connectionState == .online else { return nil }
        return session.itemImageURL(itemId: record.itemId, kind: "Primary", maxWidth: 520)
    }

    private func metaLine(for record: DownloadRecord) -> String {
        var parts: [String] = []

        if let series = record.seriesName {
            parts.append(series)
        }

        if record.seriesName != nil, let s = record.seasonNumber, let e = record.episodeNumber {
            parts.append("S\(s)E\(e)")
        }

        if let expected = record.bytesExpected, expected > 0 {
            parts.append(byteString(expected))
        }

        return parts.isEmpty ? "Offline" : parts.joined(separator: " • ")
    }

    private func statusPill(for record: DownloadRecord) -> some View {
        Text(statusText(record))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(BrockbusterTheme.brockDark)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(BrockbusterTheme.brockGold.opacity(0.9))
            )
    }

    private func statusText(_ record: DownloadRecord) -> String {
        switch record.state {
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Offline"
        case .failed: return "Failed"
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private func formatRuntime(_ ticks: Int) -> String {
        // 10,000,000 ticks = 1 second
        let seconds = Double(ticks) / 10_000_000.0
        let minutes = Int(seconds / 60.0)
        let hrs = minutes / 60
        let mins = minutes % 60
        if hrs > 0 { return "\(hrs)h \(mins)m" }
        return "\(mins)m"
    }
}

private func formattedDate(_ date: Date) -> String {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .none
    return df.string(from: date)
}

private struct KeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.75))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct DownloadedPoster: View {
    let posterURL: URL?
    let fallbackRemoteURL: URL?

    var body: some View {
        Group {
            if let posterURL {
                LocalOrRemoteImage(url: posterURL)
            } else if let fallbackRemoteURL {
                BBCachedAsyncImage(url: fallbackRemoteURL) { phase in
                    switch phase {
                    case .empty:
                        return AnyView(
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                ProgressView()
                            }
                        )
                    case .success(let image):
                        return AnyView(
                            image
                                .resizable()
                                .scaledToFill()
                        )
                    case .failure:
                        return AnyView(
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                Image(systemName: "photo")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.70))
                            }
                        )
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)

                    Image(systemName: "film")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.70))
                }
            }
        }
        .clipped()
    }
}

/// Renders either a local file URL image or a remote URL image.
private struct LocalOrRemoteImage: View {
    let url: URL

    @State private var image: Image? = nil

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    ProgressView()
                }
                .task {
                    await load()
                }
            }
        }
    }

    private func load() async {
        if url.isFileURL {
            #if os(iOS) || os(tvOS) || os(watchOS)
            if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                image = Image(uiImage: ui)
            }
            #elseif os(macOS)
            if let data = try? Data(contentsOf: url), let ns = NSImage(data: data) {
                image = Image(nsImage: ns)
            }
            #endif
        } else {
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                #if os(iOS) || os(tvOS) || os(watchOS)
                if let ui = UIImage(data: data) {
                    image = Image(uiImage: ui)
                }
                #elseif os(macOS)
                if let ns = NSImage(data: data) {
                    image = Image(nsImage: ns)
                }
                #endif
            }
        }
    }
}
