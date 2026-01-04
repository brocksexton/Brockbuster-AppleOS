import SwiftUI

/// Offline-first experience shown when the app cannot reach the Jellyfin server.
///
/// The primary objective is to avoid a "blank" app when Brockbuster is unreachable.
/// Users should be guided to their offline downloads and given a clear retry path.
struct OfflineServerView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var downloads: DownloadManager

    private var hasAnyDownloads: Bool {
        // Do not filter by user; offline mode should show whatever is available on this device.
        let serverKey = session.serverURL.host ?? session.serverURL.absoluteString
        return downloads.records.contains(where: { $0.serverKey == serverKey && $0.state == .completed })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        BrockbusterTheme.brockDark.opacity(0.75),
                        BrockbusterTheme.brockBlue.opacity(0.55)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(BrockbusterTheme.brockGold)

                    VStack(spacing: 8) {
                        Text("Sorry, we can't connect to Brockbuster right now")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(BrockbusterTheme.brockLight)
                            .multilineTextAlignment(.center)

                        Text(subtitleText)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }

                    VStack(spacing: 12) {
                        if hasAnyDownloads {
                            NavigationLink {
                                DownloadsView()
                            } label: {
                                Label("View Downloads", systemImage: "arrow.down.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(BrockbusterTheme.brockGold)
                        }

                        Button {
                            Task { await session.refreshConnectionStatus(userInitiated: true) }
                        } label: {
                            Label("Retry Connection", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(BrockbusterTheme.brockLight.opacity(0.9))
                    }
                    .padding(.horizontal, 28)

                    if let err = session.lastConnectionError {
                        Text(err)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(BrockbusterTheme.brockLight.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }

                    Spacer(minLength: 10)
                }
                .padding(.top, 22)
            }
            .navigationTitle("Offline")
            #if !os(macOS)
            .bbNavigationTitleInline()
            #endif
        }
        .onAppear {
            // Re-check when the view appears, but do not auto-exit offline mode.
            // This prevents rapid view switching when connectivity is intermittent.
            Task { await session.refreshConnectionStatus(userInitiated: false) }
        }
    }

    private var subtitleText: String {
        if hasAnyDownloads {
            return "You can still watch anything you've downloaded. Tap Retry when you're ready to reconnect."
        }
        return "Please check your connection and try again. If you download content first, it will be available here offline."
    }
}
