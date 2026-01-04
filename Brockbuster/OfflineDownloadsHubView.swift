import SwiftUI

/// Offline downloads entry point that works even when the user is not signed in.
///
/// Downloads are stored locally on-device. This view groups downloads by
/// `serverKey` so the user can access content even when the active session
/// is logged out or pointed at a different server URL.
struct OfflineDownloadsHubView: View {
    @EnvironmentObject private var downloads: DownloadManager

    private var groupedServerKeys: [String] {
        let keys = Set(downloads.records.map { $0.serverKey })
        return keys.sorted()
    }

    private func hasAnyDownloads(for serverKey: String) -> Bool {
        downloads.records.contains(where: {
            $0.serverKey == serverKey && (
                $0.state == .completed ||
                $0.state == .downloading ||
                $0.state == .paused ||
                $0.state == .queued
            )
        })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        BrockbusterTheme.brockDark.opacity(0.72),
                        BrockbusterTheme.brockBlue.opacity(0.62)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        if groupedServerKeys.isEmpty {
                            OfflineEmptyDownloadsCard()
                        } else if groupedServerKeys.count == 1, let only = groupedServerKeys.first {
                            NavigationLink {
                                DownloadsView(serverKeyOverride: only)
                            } label: {
                                ServerCard(serverKey: only, subtitle: "Offline on this device")
                            }
                            .buttonStyle(.plain)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(groupedServerKeys, id: \.self) { key in
                                    if hasAnyDownloads(for: key) {
                                        NavigationLink {
                                            DownloadsView(serverKeyOverride: key)
                                        } label: {
                                            ServerCard(serverKey: key, subtitle: "Offline on this device")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 16)
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("Offline Downloads")
            #if !os(macOS)
            .bbNavigationTitleInline()
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Offline Downloads")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight)

            Text("Watch downloaded content without an internet connection.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))
        }
        .padding(.top, 4)
    }
}

private struct ServerCard: View {
    let serverKey: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(BrockbusterTheme.brockGold.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(BrockbusterTheme.brockGold)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(serverKey)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.72))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BrockbusterTheme.brockGold)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrockbusterTheme.brockBlue.opacity(0.35), lineWidth: 1)
        )
    }
}

/// Local empty-state card for the offline downloads hub.
///
/// `DownloadsView` has its own private EmptyDownloadsCard, but that isn't
/// visible here.
private struct OfflineEmptyDownloadsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(BrockbusterTheme.brockGold)
                Text("No downloads yet")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight)
            }

            Text("To download a movie or episode, open it and tap Download. Once saved, it will appear here even if Brockbuster is offline.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.72))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrockbusterTheme.brockBlue.opacity(0.35), lineWidth: 1)
        )
    }
}
