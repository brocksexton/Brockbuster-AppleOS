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
                            .textFieldStyle(RoundedBorderTextFieldStyle())
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
                    }
                }
                // Optionally a reset button to revert to default server
                if session.serverURL != SessionStore.defaultServerURL {
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
            // Pre-fill the text field with the current server string
            urlString = session.serverURL.absoluteString
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

    /// Reset the server to the default address.
    private func resetToDefault() {
        urlString = SessionStore.defaultServerURL.absoluteString
        submit()
    }
}
