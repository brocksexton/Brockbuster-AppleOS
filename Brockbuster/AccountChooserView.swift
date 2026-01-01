import SwiftUI

/// If the device has one or more remembered accounts, this screen lets the user
/// quickly continue as one of them or add another account.
///
/// This view is intentionally "Brockbuster" first: cinematic surfaces, soft depth,
/// and quick, confident motion without feeling like a generic Settings screen.
struct AccountChooserView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var accounts: AccountManager

    @State private var showingAddAccount = false
    @State private var errorMessage: String?
    @State private var isSigningIn: Bool = false
    @State private var selectedAccountId: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                chooserBackground

                ScrollView {
                    VStack(spacing: 18) {
                        header

                        if let errorMessage {
                            ErrorPill(message: errorMessage)
                                .padding(.horizontal)
                                .transition(.opacity)
                        }

                        VStack(spacing: 12) {
                            ForEach(accounts.rememberedAccounts) { acct in
                                AccountCard(
                                    displayName: acct.displayName ?? acct.username,
                                    subtitle: acct.serverURL?.host ?? acct.serverURLString,
                                    isSelected: selectedAccountId == acct.id,
                                    lastUsedAt: acct.lastUsedAt
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                        selectedAccountId = acct.id
                                    }
                                    signIn(acct)
                                }
                            }
                        }
                        .padding(.horizontal)

                        addAccountButton
                            .padding(.horizontal)
                            .padding(.top, 6)

                        footer
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 22)
                }
                .scrollIndicators(.hidden)

                if isSigningIn {
                    RetroLoadingView(showsLogo: true, status: "Signing in…")
                        .transition(.opacity)
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showingAddAccount) {
                NavigationStack {
                    LoginView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") { showingAddAccount = false }
                            }
                        }
                }
            }
        }
    }

    private var chooserBackground: some View {
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

            // Subtle cinematic vignette + depth.
            RadialGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.35), Color.clear]),
                center: .top,
                startRadius: 80,
                endRadius: 520
            )
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 10)

            VStack(spacing: 4) {
                Text("Welcome back")
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)

                Text("Continue with a remembered account, or add a new one.")
                    .font(.footnote)
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.78))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
    }

    private var addAccountButton: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                showingAddAccount = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")
                Text("Add another account")
                    .font(BrockbusterTheme.Fonts.body.weight(.bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .opacity(0.85)
            }
            .foregroundColor(BrockbusterTheme.brockDark)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BrockbusterTheme.brockGold)
                    .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add another account")
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("Tokens are stored securely in Keychain.")
                .font(.caption)
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.7))
        }
        .padding(.top, 10)
    }

    private func signIn(_ acct: AccountManager.SavedAccount) {
        errorMessage = nil
        guard let serverURL = acct.serverURL else {
            errorMessage = "This account has an invalid server URL saved. Please remove it and add it again."
            return
        }
        guard let token = accounts.token(for: acct) else {
            errorMessage = "We couldn't find a saved sign-in token for this account. Please sign in again."
            return
        }

        isSigningIn = true
        let user = JellyfinUser(id: acct.userId, name: acct.username, primaryImageTag: nil)
        session.restoreSession(serverURL: serverURL, user: user, accessToken: token, memberSince: acct.memberSince)
        accounts.setLastSelected(acct.id)

        Task {
            do {
                try await session.fetchLibraries()
                withAnimation(.easeOut(duration: 0.18)) {
                    isSigningIn = false
                }
            } catch {
                session.logout()
                withAnimation(.easeOut(duration: 0.18)) {
                    isSigningIn = false
                }
                errorMessage = "That saved session is no longer valid. Please sign in again."
                showingAddAccount = true
            }
        }
    }
}

// MARK: - Components

private struct AccountCard: View {
    let displayName: String
    let subtitle: String
    let isSelected: Bool
    let lastUsedAt: Date

    var body: some View {
        HStack(spacing: 14) {
            InitialsAvatar(name: displayName)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Last used \(lastUsedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 10)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.28 : 0.14), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 10)
        )
        .scaleEffect(isSelected ? 0.99 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isSelected)
    }
}

private struct InitialsAvatar: View {
    let name: String

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "B"
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(BrockbusterTheme.brockGold.opacity(0.22))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
            Text(initials)
                .font(.headline.weight(.bold))
                .foregroundColor(.primary)
        }
        .frame(width: 46, height: 46)
    }
}

private struct ErrorPill: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.footnote)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.red.opacity(0.55))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

#if DEBUG
struct AccountChooserView_Previews: PreviewProvider {
    static var previews: some View {
        AccountChooserView()
            .environmentObject(SessionStore())
            .environmentObject(AccountManager())
    }
}
#endif
