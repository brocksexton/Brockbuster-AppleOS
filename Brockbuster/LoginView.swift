import SwiftUI

/// The authentication screen presented when a user needs to sign into their
/// Jellyfin account.  Incorporates the Brockbuster branding with a glass card
/// form, custom ticket buttons and a retro loading overlay.  Professional
/// typography and spacing give a premium feel while still nodding to the
/// Blockbuster aesthetic.
struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var accountManager: AccountManager
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @AppStorage("settings.defaultRememberAccount") private var defaultRememberAccount: Bool = true
    @State private var rememberThisAccount: Bool = true
    // Tracks whether the configured server is reachable.  nil indicates that
    // reachability is still being checked.
    @State private var serverReachable: Bool? = nil
    // Controls display of the connectivity info alert.
    @State private var showInfoAlert: Bool = false

    var body: some View {
        ZStack {
            // Vibrant blurred background using Brockbuster colours
            LinearGradient(gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.6), BrockbusterTheme.brockBlue.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            // Content stack
            VStack(spacing: 32) {
                Spacer()
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .shadow(radius: 20)
                Text("Sign In")
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)
                // Connectivity indicator row
                HStack(spacing: 8) {
                    // Coloured dot representing server health
                    Circle()
                        .fill(serverReachable == nil ? Color.gray : (serverReachable == true ? Color.green : Color.red))
                        .frame(width: 10, height: 10)
                    Text(serverReachable == nil ? "Checking server…" : (serverReachable == true ? "Server Online" : "Server Offline"))
                        .font(.footnote)
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                    Spacer()
                    // Info button to learn more about connectivity issues
                    Button(action: { showInfoAlert = true }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(BrockbusterTheme.brockGold)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Username")
                                .font(BrockbusterTheme.Fonts.body.weight(.semibold))
                                .foregroundColor(BrockbusterTheme.textPrimary)
                            TextField("Your username", text: $username)
                                .bbTextFieldStyle()
                                #if os(iOS) || os(tvOS)
                                .disableAutocorrection(true)
                                .autocapitalization(.none)
                                #endif
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Password")
                                .font(BrockbusterTheme.Fonts.body.weight(.semibold))
                                .foregroundColor(BrockbusterTheme.textPrimary)
                            SecureField("Your password", text: $password)
                                .bbTextFieldStyle()
                        }
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.footnote)
                        }

                        Toggle("Remember this account on this device", isOn: $rememberThisAccount)
                            .font(.footnote)
                            .tint(BrockbusterTheme.brockGold)
                        Button(action: login) {
                            Text("Login")
                                .font(BrockbusterTheme.Fonts.body.weight(.bold))
                        }
                        .buttonStyle(BrockbusterTheme.TicketButtonStyle())
                        // A subtle secondary action to change the server
                        Button(action: session.resetServer) {
                            Text("Change Server")
                                .font(.footnote)
                                .underline()
                        }
                        .foregroundColor(BrockbusterTheme.brockGold)
                        .padding(.top, 4)
                    }
                }
                Spacer()
            }
            .padding()
            // Loading overlay
            if isLoading {
                RetroLoadingView(showsLogo: true, status: "Signing in…")
                    .transition(.opacity)
            }
        }
        // Present an alert with troubleshooting tips if the user taps the info button
        .alert("Connection Tips", isPresented: $showInfoAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text("If the server appears offline, please check that your device is connected to the internet and that the server URL is correct.\n\nIf you're using a VPN, try disabling it or allow-listing Jellyfin.\n\nYou can also open the server address in Safari or another browser to verify it's reachable.")
        })
        .onAppear {
            // Clear credentials when returning to login screen
            username = ""
            password = ""
            // Keep the toggle aligned with the user's preference.
            rememberThisAccount = defaultRememberAccount
            // Check the server's health status on appear
            Task {
                serverReachable = nil
                let reachable = await session.pingServer()
                serverReachable = reachable
            }
        }
    }

    /// Attempt to authenticate using the provided credentials.
    private func login() {
        Task {
            errorMessage = nil
            isLoading = true
            do {
                try await session.login(username: username, password: password)
                // Persist the session as a remembered account if the user asked for it.
                if rememberThisAccount,
                   let user = session.currentUser,
                   let token = session.accessToken {
                    accountManager.upsertAccount(
                        serverURL: session.serverURL,
                        user: user,
                        accessToken: token,
                        remembered: true,
                        memberSince: session.joinDate
                    )
                }
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
