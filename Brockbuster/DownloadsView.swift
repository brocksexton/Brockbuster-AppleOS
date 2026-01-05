import SwiftUI

/// Displays and manages offline downloads.
struct DownloadsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var downloads: DownloadManager

    /// Optional override so downloads can be browsed even when the user is not
    /// signed in (or when the session is pointed at a different server).
    let serverKeyOverride: String?

    init(serverKeyOverride: String? = nil) {
        self.serverKeyOverride = serverKeyOverride
    }

    @State private var sortOption: SortOption = .recent
    @State private var isManaging: Bool = false

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

                    controls

                    if activeRecords.isEmpty && completedRecords.isEmpty && failedRecords.isEmpty {
                        EmptyDownloadsCard()
                    } else {
                        if !activeRecords.isEmpty {
                            SectionHeader(title: "Downloading", subtitle: "In progress")
                            VStack(spacing: 10) {
                                ForEach(activeRecords) { rec in
                                    DownloadRow(
                                        record: rec,
                                        posterURL: downloads.cachedPosterURL(for: rec) ?? remotePosterURL(for: rec),
                                        isManaging: isManaging
                                    ) {
                                        downloads.remove(record: rec)
                                    }
                                }
                            }
                        }

                        if !completedRecords.isEmpty {
                            SectionHeader(title: "Downloaded", subtitle: "Available offline")
                            VStack(spacing: 10) {
                                ForEach(completedRecords) { rec in
                                    NavigationLink {
                                        DownloadedItemDetailView(recordId: rec.id)
                                    } label: {
                                        DownloadRow(
                                            record: rec,
                                            posterURL: downloads.cachedPosterURL(for: rec) ?? remotePosterURL(for: rec),
                                            isManaging: isManaging
                                        ) {
                                            downloads.remove(record: rec)
                                        }
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
                                    DownloadRow(
                                        record: rec,
                                        posterURL: downloads.cachedPosterURL(for: rec) ?? remotePosterURL(for: rec),
                                        isManaging: isManaging
                                    ) {
                                        downloads.remove(record: rec)
                                    }
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
        serverKeyOverride ?? (session.serverURL.host ?? session.serverURL.absoluteString)
    }

    private var activeRecords: [DownloadRecord] {
        sorted(scopedRecords
            .filter { $0.state == .queued || $0.state == .downloading || $0.state == .paused })
    }

    private var completedRecords: [DownloadRecord] {
        sorted(scopedRecords
            .filter { $0.state == .completed })
    }

    private var failedRecords: [DownloadRecord] {
        sorted(scopedRecords
            .filter { $0.state == .failed })
    }

    private enum SortOption: String, CaseIterable, Identifiable {
        case recent = "Recently added"
        case title = "Title"
        case series = "Series"
        case size = "Size"
        case progress = "Progress"

        var id: String { rawValue }
    }

    private func sorted(_ records: [DownloadRecord]) -> [DownloadRecord] {
        switch sortOption {
        case .recent:
            return records.sorted { $0.updatedAt > $1.updatedAt }
        case .title:
            return records.sorted { $0.itemName.localizedCaseInsensitiveCompare($1.itemName) == .orderedAscending }
        case .series:
            return records.sorted {
                let a = ($0.seriesName ?? "").lowercased()
                let b = ($1.seriesName ?? "").lowercased()
                if a == b { return $0.itemName.lowercased() < $1.itemName.lowercased() }
                return a < b
            }
        case .size:
            return records.sorted { ($0.bytesExpected ?? 0) > ($1.bytesExpected ?? 0) }
        case .progress:
            return records.sorted { $0.progress > $1.progress }
        }
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

    private var controls: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Sort", selection: $sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(BrockbusterTheme.brockBlue.opacity(0.35), lineWidth: 1)
                    )
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isManaging.toggle()
                }
            } label: {
                Text(isManaging ? "Done" : "Edit")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(isManaging ? BrockbusterTheme.brockDark : BrockbusterTheme.brockLight)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Group {
                            if isManaging {
                                Capsule().fill(BrockbusterTheme.brockGold.opacity(0.9))
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                    )
                    .overlay(
                        Capsule().stroke(BrockbusterTheme.brockBlue.opacity(0.35), lineWidth: 1)
                    )
            }
        }
        .padding(.top, 2)
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

    private func remotePosterURL(for record: DownloadRecord) -> URL? {
        guard session.connectionState == .online else { return nil }
        return session.itemImageURL(itemId: record.itemId, kind: "Primary", maxWidth: 360)
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
    let posterURL: URL?
    var isManaging: Bool = false
    var onDelete: (() -> Void)? = nil

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    DownloadRowPoster(url: posterURL)
                        .frame(width: 54, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BrockbusterTheme.brockBlue.opacity(0.30), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                        Text(record.itemName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(BrockbusterTheme.brockLight)

                        if let sub = subtitle {
                            Text(sub)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.72))
                        }

                        if let meta = metaLine {
                            Text(meta)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.60))
                        }
                        }

                        Spacer(minLength: 0)

                        HStack(spacing: 10) {
                            statusPill
                            kindPill

                            if isManaging, let onDelete {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.red.opacity(0.92))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(.ultraThinMaterial)
                                    )
                                    .overlay(
                                        Capsule().stroke(BrockbusterTheme.brockBlue.opacity(0.35), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if record.state == .downloading || record.state == .queued {
                    if let expected = record.bytesExpected, expected > 0 {
                        ProgressView(value: record.progress)
                            .tint(BrockbusterTheme.brockGold)
                    } else {
                        // If the server does not provide an expected size, fall back
                        // to an indeterminate progress indicator.
                        ProgressView()
                            .tint(BrockbusterTheme.brockGold)
                    }
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

    private var metaLine: String? {
        var parts: [String] = []
        // Source format flags (best-effort)
        if let c = record.sourceContainer, !c.isEmpty { parts.append(c.uppercased()) }
        if let v = record.sourceVideoCodec, !v.isEmpty { parts.append(v.uppercased()) }
        if let a = record.sourceAudioCodec, !a.isEmpty { parts.append(a.uppercased()) }

        if let expected = record.bytesExpected, expected > 0 {
            let f = ByteCountFormatter()
            f.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
            f.countStyle = .file
            parts.append(f.string(fromByteCount: expected))
        } else if let written = record.bytesWritten, written > 0 {
            let f = ByteCountFormatter()
            f.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
            f.countStyle = .file
            parts.append(f.string(fromByteCount: written))
        }

        // Show a compact timestamp for user confidence (especially when sorting by Recent).
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        parts.append(df.string(from: record.updatedAt))

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var kindPill: some View {
        let kind = record.downloadKind ?? ((record.usedCompatibility ?? false) ? .transcoded : .direct)
        let text = (kind == .transcoded) ? "Transcoded" : "Direct"
        return Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(BrockbusterTheme.brockLight)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(
                Capsule().stroke(
                    (kind == .transcoded ? BrockbusterTheme.brockGold : BrockbusterTheme.brockBlue).opacity(0.55),
                    lineWidth: 1
                )
            )
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
            if let expected = record.bytesExpected, expected > 0 {
                return "\(Int(record.progress * 100))%"
            }
            return "Downloading"
        case .paused:
            return "Paused"
        case .completed:
            return "Offline"
        case .failed:
            return "Failed"
        }
    }
}

private struct DownloadRowPoster: View {
    let url: URL?

    @State private var image: Image? = nil

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)

                    Image(systemName: "film")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.70))
                }
                .task {
                    await load()
                }
            }
        }
        .clipped()
    }

    private func load() async {
        guard let url else { return }
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
