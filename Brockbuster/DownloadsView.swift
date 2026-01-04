import SwiftUI

/// Displays and manages offline downloads.
struct DownloadsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    BrockbusterTheme.brockDark.opacity(0.65),
                    BrockbusterTheme.brockBlue.opacity(0.55)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if activeRecords.isEmpty && completedRecords.isEmpty && failedRecords.isEmpty {
                        EmptyDownloadsCard()
                    } else {
                        if !activeRecords.isEmpty {
                            SectionHeader(title: "Downloading", subtitle: "In progress")
                            VStack(spacing: 10) {
                                ForEach(activeRecords) { rec in
                                    DownloadRow(record: rec)
                                }
                            }
                        }

                        if !completedRecords.isEmpty {
                            SectionHeader(title: "Downloaded", subtitle: "Available offline")
                            VStack(spacing: 10) {
                                ForEach(completedRecords) { rec in
                                    NavigationLink {
                                        offlineDestination(for: rec)
                                    } label: {
                                        DownloadRow(record: rec)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            downloads.remove(record: rec)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            downloads.remove(record: rec)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }

                        if !failedRecords.isEmpty {
                            SectionHeader(title: "Failed", subtitle: "Needs attention")
                            VStack(spacing: 10) {
                                ForEach(failedRecords) { rec in
                                    DownloadRow(record: rec)
                                        .contextMenu {
                                            Button {
                                                downloads.enqueue(item: JellyfinClient.LibraryItem(
                                                    id: rec.itemId,
                                                    name: rec.itemName,
                                                    type: rec.mediaType,
                                                    mediaType: rec.mediaType,
                                                    runtimeTicks: nil,
                                                    primaryImageTag: nil,
                                                    overview: nil,
                                                    productionYear: nil,
                                                    premiereDate: nil,
                                                    indexNumber: rec.episodeNumber,
                                                    parentIndexNumber: rec.seasonNumber,
                                                    seriesId: nil,
                                                    seasonId: nil,
                                                    seriesName: rec.seriesName,
                                                    userData: nil
                                                ), sessionStore: session, entryPoint: "downloads_retry")
                                            } label: {
                                                Label("Retry", systemImage: "arrow.clockwise")
                                            }
                                            Button(role: .destructive) {
                                                downloads.remove(record: rec)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button {
                                                downloads.enqueue(item: JellyfinClient.LibraryItem(
                                                    id: rec.itemId,
                                                    name: rec.itemName,
                                                    type: rec.mediaType,
                                                    mediaType: rec.mediaType,
                                                    runtimeTicks: nil,
                                                    primaryImageTag: nil,
                                                    overview: nil,
                                                    productionYear: nil,
                                                    premiereDate: nil,
                                                    indexNumber: rec.episodeNumber,
                                                    parentIndexNumber: rec.seasonNumber,
                                                    seriesId: nil,
                                                    seasonId: nil,
                                                    seriesName: rec.seriesName,
                                                    userData: nil
                                                ), sessionStore: session, entryPoint: "downloads_retry")
                                            } label: {
                                                Label("Retry", systemImage: "arrow.clockwise")
                                            }
                                            .tint(.blue)

                                            Button(role: .destructive) {
                                                downloads.remove(record: rec)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        }
        .navigationTitle("Downloads")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
    }

    private var serverKey: String {
        session.serverURL.host ?? session.serverURL.absoluteString
    }

    private var activeRecords: [DownloadRecord] {
        scopedRecords
            .filter { $0.state == .queued || $0.state == .downloading || $0.state == .paused }
    }

    private var completedRecords: [DownloadRecord] {
        scopedRecords
            .filter { $0.state == .completed }
    }

    private var failedRecords: [DownloadRecord] {
        scopedRecords
            .filter { $0.state == .failed }
    }

    /// When offline (or if the session user is temporarily nil), we still want to show
    /// downloads for this server. Filtering strictly by currentUser can make a completed
    /// download appear to "disappear" even though it exists on disk.
    private var scopedRecords: [DownloadRecord] {
        let userId = session.currentUser?.id
        return downloads.records
            .filter { $0.serverKey == serverKey }
            .filter { userId == nil ? true : ($0.userId == userId) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Downloads")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight)

            Text("Watch offline. Downloads are stored on this device.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func offlineDestination(for record: DownloadRecord) -> some View {
        if let url = downloads.localFileURL(for: record) {
            OfflinePlayerView(
                title: record.itemName,
                subtitle: offlineSubtitle(for: record),
                url: url,
                itemId: record.itemId
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.orange)

                Text("Missing File")
                    .font(.headline)

                Text("The downloaded file could not be found. Try downloading again.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    private func offlineSubtitle(for record: DownloadRecord) -> String? {
        guard let series = record.seriesName else { return nil }
        if let s = record.seasonNumber, let e = record.episodeNumber {
            return "\(series) • S\(s) E\(e)"
        }
        return series
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight)
            Text(subtitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.75))
        }
        .padding(.top, 6)
    }
}

private struct EmptyDownloadsCard: View {
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("No downloads yet", systemImage: "arrow.down.circle")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight)

                Text("To download a movie or episode, open it and tap Download.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
            }
            .padding(14)
        }
    }
}

private struct DownloadRow: View {
    let record: DownloadRecord

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.itemName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(BrockbusterTheme.brockLight)

                        if let sub = subtitle {
                            Text(sub)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.72))
                        }
                    }

                    Spacer()

                    statusPill
                }

                if record.state == .downloading || record.state == .queued {
                    ProgressView(value: record.progress)
                        .tint(BrockbusterTheme.brockGold)
                }

                if record.state == .failed, let err = record.errorDescription {
                    Text(err)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.red.opacity(0.85))
                }
            }
            .padding(12)
        }
    }

    private var subtitle: String? {
        if let series = record.seriesName {
            if let s = record.seasonNumber, let e = record.episodeNumber {
                return "\(series) • S\(s) E\(e)"
            }
            return series
        }
        return record.mediaType
    }

    private var statusPill: some View {
        Text(statusText)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(BrockbusterTheme.brockDark)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(BrockbusterTheme.brockGold.opacity(0.9))
            )
    }

    private var statusText: String {
        switch record.state {
        case .queued:
            return "Queued"
        case .downloading:
            return "\(Int(record.progress * 100))%"
        case .paused:
            return "Paused"
        case .completed:
            return "Offline"
        case .failed:
            return "Failed"
        }
    }
}

/// Minimal local-file player wrapper.
private struct OfflinePlayerView: View {
    let title: String
    let subtitle: String?
    let url: URL
    let itemId: String

    var body: some View {
        PlayerView(
            itemId: itemId,
            url: url,
            title: title,
            subtitle: subtitle,
            posterURL: nil,
            playbackContext: nil,
            startPositionTicks: 0
        )
    }
}
