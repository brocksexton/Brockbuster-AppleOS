import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var accountManager: AccountManager

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    @AppStorage("settings.defaultRememberAccount") private var defaultRememberAccount: Bool = true
    @State private var rememberThisAccount: Bool = true

    @AppStorage("onboarding.presentNow") private var presentOnboardingNow: Bool = false

    @State private var serverReachable: Bool? = nil
    @State private var showInfoAlert: Bool = false

    @State private var logoPulse: Bool = false
    @State private var appear: Bool = false

    var body: some View {
        ZStack {
            BrockbusterLoginBackdrop(pulse: $logoPulse)

            GeometryReader { geo in
                let isCompactWidth = (horizontalSizeClass == .compact)
                let isCompactHeight = geo.size.height < 760

                #if os(tvOS)
                tvLayout(geo: geo)
                #else
                if isCompactWidth {
                    iPhoneLayout(geo: geo, isCompactHeight: isCompactHeight)
                } else {
                    iPadLayout(geo: geo, isCompactHeight: isCompactHeight)
                }
                #endif
            }

            if isLoading {
                RetroLoadingView(showsLogo: true, status: "Signing in…")
                    .transition(.opacity)
            }
        }
        .alert("Connection Tips", isPresented: $showInfoAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text("If the server appears offline, please check that your device is connected to the internet and that the server URL is correct.\n\nIf you're using a VPN, try disabling it or allow-listing Jellyfin.\n\nYou can also open the server address in Safari or another browser to verify it's reachable.")
        })
        .onAppear {
            username = ""
            password = ""
            rememberThisAccount = defaultRememberAccount

            Task {
                serverReachable = nil
                let reachable = await session.pingServer()
                serverReachable = reachable
            }

            appear = false
            withAnimation(.easeOut(duration: 0.55)) {
                appear = true
            }

            #if !os(tvOS)
            logoPulse = false
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                logoPulse = true
            }
            #else
            logoPulse = false
            #endif
        }
    }

    // MARK: - iPhone Layout (separate, width-safe)

    private func iPhoneLayout(geo: GeometryProxy, isCompactHeight: Bool) -> some View {
        let logoSize: CGFloat = isCompactHeight ? 96 : 124

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: isCompactHeight ? 14 : 20) {
                Spacer(minLength: isCompactHeight ? 8 : 14)

                // More compact, iOS-first hero.
                VStack(spacing: 12) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: logoSize, height: logoSize)
                        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 12)
                        .scaleEffect(logoPulse ? 1.02 : 0.98)

                    VStack(spacing: 4) {
                        Text("Welcome back")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(BrockbusterTheme.brockLight)

                        Text("Grab your ticket. Let’s roll.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))
                    }
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 14)

                // A single, cohesive card: status + fields + CTAs.
                iPhoneFormCard()
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 18)
                    .animation(.easeOut(duration: 0.55).delay(0.10), value: appear)

                tourButton()
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)
                    .animation(.easeOut(duration: 0.55).delay(0.14), value: appear)

                Button {
                    presentOnboardingNow = true
                } label: {
                    Label("Take a quick tour", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bordered)
                .tint(BrockbusterTheme.brockGold)

                Spacer(minLength: 18)
            }
            .frame(maxWidth: 520, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.bottom, max(24, geo.safeAreaInsets.bottom + 24))
            .padding(.top, 6)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        #endif
    }

    // MARK: - iPad Layout (keep your premium centered look)

    private func iPadLayout(geo: GeometryProxy, isCompactHeight: Bool) -> some View {
        let logoSize: CGFloat = isCompactHeight ? 110 : 150
        let iPadCardWidth: CGFloat = 560

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: isCompactHeight ? 18 : 28) {
                Spacer(minLength: isCompactHeight ? 10 : 18)

                header(logoSize: logoSize, animateLogo: true)
                    .padding(.horizontal, 28)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 14)

                connectivityRow()
                    .padding(.horizontal, 28)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)
                    .animation(.easeOut(duration: 0.45).delay(0.06), value: appear)

                formCard(maxWidth: iPadCardWidth)
                    .padding(.horizontal, 28)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 18)
                    .animation(.easeOut(duration: 0.55).delay(0.10), value: appear)

                tourButton()
                    .padding(.horizontal, 28)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)
                    .animation(.easeOut(duration: 0.55).delay(0.14), value: appear)

                Spacer(minLength: 18)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, max(24, geo.safeAreaInsets.bottom + 24))
            .padding(.top, 6)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        #endif
    }

    // MARK: - tvOS Layout (keep as-is; no logo animation)

    #if os(tvOS)
    private func tvLayout(geo: GeometryProxy) -> some View {
        let contentWidth = geo.size.width
        let sidePadding: CGFloat = 80
        let heroWidth = max(520, contentWidth * 0.48)
        let formWidth = min(620, contentWidth * 0.44)

        return ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .center, spacing: 48) {
                VStack(alignment: .leading, spacing: 18) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .shadow(color: .black.opacity(0.35), radius: 26, x: 0, y: 16)
                    // no tvOS animation

                    Text("Welcome back")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundColor(BrockbusterTheme.brockLight)

                    Text("Grab your ticket. Let’s roll.")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))

                    connectivityRow()
                        .padding(.top, 8)
                }
                .frame(width: heroWidth, alignment: .leading)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 16)

                formCard(maxWidth: formWidth)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 22)
                    .animation(.easeOut(duration: 0.6).delay(0.08), value: appear)
            }
            .frame(width: contentWidth, alignment: .center)
            .padding(.horizontal, sidePadding)
            .padding(.vertical, 60)
        }
    }
    #endif

    // MARK: - Components

    private func tourButton() -> some View {
        Button {
            presentOnboardingNow = true
        } label: {
            Label("Take a quick tour", systemImage: "sparkles")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(BrockbusterTheme.brockGold)
        .foregroundColor(BrockbusterTheme.brockDark)
    }

    private func header(logoSize: CGFloat, animateLogo: Bool) -> some View {
        VStack(spacing: 18) {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 12)
                .scaleEffect(animateLogo ? (logoPulse ? 1.03 : 0.98) : 1.0)
                .animation(animateLogo ? .spring(response: 0.8, dampingFraction: 0.7) : nil, value: logoPulse)

            VStack(spacing: 6) {
                Text("Welcome back")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight)

                Text("Grab your ticket. Let's roll.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))
            }
        }
    }

    private func connectivityRow() -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(serverReachable == nil ? Color.gray : (serverReachable == true ? Color.green : Color.red))
                .frame(width: 10, height: 10)

            Text(serverReachable == nil ? "Checking server…" : (serverReachable == true ? "Server Online" : "Server Offline"))
                .font(.footnote)
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))

            Spacer()

            Button(action: { showInfoAlert = true }) {
                Image(systemName: "info.circle")
                    .foregroundColor(BrockbusterTheme.brockGold)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func iPhoneFormCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            connectivityRow()

            VStack(alignment: .leading, spacing: 4) {
                Text("Username")
                    .font(BrockbusterTheme.Fonts.body.weight(.semibold))
                    .foregroundColor(BrockbusterTheme.textPrimary)

                TextField("Your username", text: $username)
                    .bbTextFieldStyle()
                    .frame(maxWidth: .infinity)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(BrockbusterTheme.Fonts.body.weight(.semibold))
                    .foregroundColor(BrockbusterTheme.textPrimary)

                SecureField("Your password", text: $password)
                    .bbTextFieldStyle()
                    .frame(maxWidth: .infinity)
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Remember this account on this device")
                    .font(.footnote)
                    .foregroundColor(BrockbusterTheme.textPrimary.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Toggle("", isOn: $rememberThisAccount)
                    .labelsHidden()
                    .tint(BrockbusterTheme.brockGold)
                    .transaction { $0.animation = nil }
            }

            Button(action: login) {
                Text("Enter Brockbuster")
                    .font(BrockbusterTheme.Fonts.body.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BrockbusterTheme.TicketButtonStyle())

            Button(action: session.resetServer) {
                Text("Change Server")
                    .font(.footnote)
                    .underline()
            }
            .foregroundColor(BrockbusterTheme.brockGold)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
    }

    private func formCard(maxWidth: CGFloat) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Username")
                        .font(BrockbusterTheme.Fonts.body.weight(.semibold))
                        .foregroundColor(BrockbusterTheme.textPrimary)

                    TextField("Your username", text: $username)
                        .bbTextFieldStyle()
                        .frame(maxWidth: .infinity)
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
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }

                Toggle("Remember this account on this device", isOn: $rememberThisAccount)
                    .font(.footnote)
                    .tint(BrockbusterTheme.brockGold)
                #if os(iOS)
                    .transaction { $0.animation = nil }
                #endif

                Button(action: login) {
                    Text("Enter Brockbuster")
                        .font(BrockbusterTheme.Fonts.body.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BrockbusterTheme.TicketButtonStyle())

                Button(action: session.resetServer) {
                    Text("Change Server")
                        .font(.footnote)
                        .underline()
                }
                .foregroundColor(BrockbusterTheme.brockGold)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: maxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Login

    private func login() {
        Task {
            errorMessage = nil
            isLoading = true
            do {
                try await session.login(username: username, password: password)

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

// MARK: - Premium login backdrop

private struct BrockbusterLoginBackdrop: View {
    @Binding var pulse: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    BrockbusterTheme.brockDark.opacity(0.72),
                    BrockbusterTheme.brockBlue.opacity(0.62)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(BrockbusterTheme.brockGold.opacity(0.14))
                .frame(width: 420, height: 420)
                .blur(radius: 18)
                .offset(x: pulse ? 120 : 80, y: pulse ? -240 : -200)

            Circle()
                .fill(BrockbusterTheme.brockBlue.opacity(0.22))
                .frame(width: 520, height: 520)
                .blur(radius: 22)
                .offset(x: pulse ? -160 : -120, y: pulse ? 260 : 220)

            RadialGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)]),
                center: .center,
                startRadius: 80,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}
