import SwiftUI

/// Optional: when the user disables the account chooser on launch, we attempt to
/// restore the last selected remembered account automatically.
///
/// If restore fails, we fall back to AccountChooserView.
struct AutoSignInView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var accounts: AccountManager
    @EnvironmentObject private var downloads: DownloadManager

    @State private var errorMessage: String?
    @State private var isWorking: Bool = true
    @State private var fallbackToChooser: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if fallbackToChooser {
                    AccountChooserView()
                } else {
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

                        VStack(spacing: 14) {
                            Spacer()

                            Image("logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 10)

                            Text("Signing you in…")
                                .font(BrockbusterTheme.Fonts.title)
                                .foregroundColor(BrockbusterTheme.brockLight)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal)
                            }

                            Button {
                                fallbackToChooser = true
                            } label: {
                                Text("Use another account")
                                    .font(BrockbusterTheme.Fonts.body.weight(.bold))
                                    .foregroundColor(BrockbusterTheme.brockGold)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)

                            // Offline downloads should be reachable even when session restore fails.
                            if downloads.records.contains(where: { $0.state == .completed }) {
                                NavigationLink {
                                    OfflineDownloadsHubView()
                                } label: {
                                    Text("Offline Downloads")
                                        .font(BrockbusterTheme.Fonts.body.weight(.bold))
                                        .foregroundColor(BrockbusterTheme.brockLight)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(.ultraThinMaterial)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .stroke(BrockbusterTheme.brockBlue.opacity(0.35), lineWidth: 1)
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                            }

                            Spacer()
                        }

                        if isWorking {
                            RetroLoadingView(showsLogo: false, status: "")
                                .transition(.opacity)
                        }
                    }
                    .onAppear { attemptRestore() }
                }
            }
        }
    }

    private func attemptRestore() {
        errorMessage = nil
        isWorking = true

        guard let lastId = accounts.lastSelectedAccountId(),
              let acct = accounts.accounts.first(where: { $0.id == lastId }),
              acct.remembered
        else {
            // No viable last account; use chooser.
            fallbackToChooser = true
            isWorking = false
            return
        }

        guard let serverURL = acct.serverURL, let token = accounts.token(for: acct) else {
            fallbackToChooser = true
            isWorking = false
            return
        }

        let user = JellyfinUser(id: acct.userId, name: acct.username, primaryImageTag: nil)
        session.restoreSession(serverURL: serverURL, user: user, accessToken: token, memberSince: acct.memberSince)

        Task {
            do {
                try await session.fetchLibraries()
                withAnimation(.easeOut(duration: 0.18)) {
                    isWorking = false
                }
            } catch {
                session.logout()
                withAnimation(.easeOut(duration: 0.18)) {
                    isWorking = false
                    errorMessage = "Saved session expired. Choose an account to sign in again."
                    fallbackToChooser = true
                }
            }
        }
    }
}
