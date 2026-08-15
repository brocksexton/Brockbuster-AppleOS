import SwiftUI

/// A view that allows the user to specify or verify the Jellyfin server URL.  It
/// appears when no server has been configured or when the user chooses to
/// change the server from the login or home screens.  The view validates the
/// given URL by checking the `/health` endpoint before proceeding.
struct ServerSetupView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var urlString: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    @AppStorage("onboarding.presentNow") private var presentOnboardingNow: Bool = false

    var body: some View {
        ZStack {
            BrockbusterTheme.brockDark
                .ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                // Logo at top
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .shadow(radius: 10)
                Text("Connect to Server")
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)
                    .padding(.bottom, 4)
                Text("Enter the address of your Jellyfin server")
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(BrockbusterTheme.textSecondary)
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Server URL")
                            .font(BrockbusterTheme.Fonts.body.weight(.semibold))
                            .foregroundColor(BrockbusterTheme.textPrimary)
                        TextField("https://example.com", text: $urlString)
                            .bbTextFieldStyle()
                            #if os(iOS) || os(tvOS)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            #endif
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.footnote)
                        }
                        Button(action: submit) {
                            Text("Continue")
                                .font(BrockbusterTheme.Fonts.body.weight(.bold))
                        }
                        .buttonStyle(BrockbusterTheme.TicketButtonStyle())

                        Button {
                            presentOnboardingNow = true
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Take a quick tour")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(BrockbusterTheme.brockGold)
                    }
                }

                // Optionally a reset button to revert to the bundled default
                // server (only offered when this build ships one).
                if let defaultURL = SessionStore.defaultServerURL, session.serverURL != defaultURL {
                    Button(action: resetToDefault) {
                        Text("Use Default Server")
                    }
                    .foregroundColor(BrockbusterTheme.brockGold)
                    .padding(.top, 8)
                }
                Spacer()
            }
            .padding()
            // Show loading overlay when validating
            if isLoading {
                RetroLoadingView(showsLogo: true, status: "Connecting…")
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Pre-fill the text field with the current server string, unless no
            // server has been configured yet (fresh install) — then start empty.
            urlString = session.hasConfiguredServer ? session.serverURL.absoluteString : ""
        }
    }

    /// Attempt to validate the server URL and update the session on success.
    private func submit() {
        Task {
            errorMessage = nil
            isLoading = true
            do {
                try await session.validateServer(urlString: urlString)
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Reset the server to the bundled default address, when one exists.
    private func resetToDefault() {
        guard let defaultURL = SessionStore.defaultServerURL else { return }
        urlString = defaultURL.absoluteString
        submit()
    }
}
