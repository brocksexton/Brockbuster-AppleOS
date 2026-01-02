import SwiftUI

/// A consolidated list of secondary screens that don't need their own bottom-tab.
/// This menu is intended to be extensible as Brockbuster grows (accounts, friends,
/// stats/health, settings, etc.).
struct MoreView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showingLogoutConfirm = false

    var body: some View {
        #if os(tvOS)
        tvLayout
        #else
        List {
            Section("Account") {
                NavigationLink(destination: MembershipCardView()) {
                    Label("Membership", systemImage: "wallet.pass")
                }

                NavigationLink(destination: ServerSetupView()) {
                    Label("Server & Login", systemImage: "server.rack")
                }

                NavigationLink(destination: SettingsTab()) {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }

            Section("Community") {
                NavigationLink(destination: FriendsView()) {
                    Label("Friends", systemImage: "person.2.fill")
                }

                NavigationLink(destination: SocialTab()) {
                    Label("Social Feed", systemImage: "quote.bubble.fill")
                }

                NavigationLink(destination: PeopleView()) {
                    Label("People", systemImage: "person.crop.square")
                }
            }

            Section("System") {
                NavigationLink(destination: ServerHealthTab()) {
                    Label("Server Health", systemImage: "waveform.path.ecg")
                }
            }

            Section {
                Button(role: .destructive) {
                    showingLogoutConfirm = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("More")
        #if !os(macOS)
        .bbNavigationTitleLarge()
        #endif
        .alert("Sign out of Brockbuster?", isPresented: $showingLogoutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                session.logout()
            }
        } message: {
            Text("You will need to sign in again to access your libraries.")
        }
        #endif
    }

    #if os(tvOS)
    private var tvLayout: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.65), BrockbusterTheme.brockBlue.opacity(0.55)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("More")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(BrockbusterTheme.brockLight)
                        .padding(.top, 6)

                    MoreSectionCard(title: "Account") {
                        MoreRowLink(title: "Membership", systemImage: "wallet.pass") {
                            MembershipCardView()
                        }
                        MoreRowLink(title: "Server & Login", systemImage: "server.rack") {
                            ServerSetupView()
                        }
                        MoreRowLink(title: "Settings", systemImage: "gearshape.fill") {
                            SettingsTab()
                        }
                    }

                    MoreSectionCard(title: "Community") {
                        MoreRowLink(title: "Friends", systemImage: "person.2.fill") {
                            FriendsView()
                        }
                        MoreRowLink(title: "Social Feed", systemImage: "quote.bubble.fill") {
                            SocialTab()
                        }
                        MoreRowLink(title: "People", systemImage: "person.crop.square") {
                            PeopleView()
                        }
                    }

                    MoreSectionCard(title: "System") {
                        MoreRowLink(title: "Server Health", systemImage: "waveform.path.ecg") {
                            ServerHealthTab()
                        }
                    }

                    MoreSectionCard(title: "") {
                        Button(role: .destructive) {
                            showingLogoutConfirm = true
                        } label: {
                            MoreRow(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right", isDestructive: true)
                        }
                        .buttonStyle(.plain)
                        .bbTVFocusCard(cornerRadius: 18)
                    }

                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 46)
                .padding(.bottom, 40)
                .frame(maxWidth: 1400, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("More")
        .bbNavigationTitleInline()
        .alert("Sign out of Brockbuster?", isPresented: $showingLogoutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                session.logout()
            }
        } message: {
            Text("You will need to sign in again to access your libraries.")
        }
    }
    #endif
}

#if os(tvOS)
private struct MoreSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.88))
                    .padding(.horizontal, 6)
            }

            VStack(spacing: 10) {
                content()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct MoreRowLink<Destination: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            MoreRow(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .bbTVFocusCard(cornerRadius: 18)
    }
}

private struct MoreRow: View {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(BrockbusterTheme.brockGold.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(BrockbusterTheme.brockGold)
            }

            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(isDestructive ? .red : BrockbusterTheme.brockLight)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
#endif

/// Placeholder settings view to demonstrate adding additional pages. You can
/// customize this with real settings for the app such as theme, cache management,
/// and account linking.
struct SettingsTab: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var accountManager: AccountManager

    @AppStorage("settings.defaultRememberAccount") private var defaultRememberAccount: Bool = true
    @AppStorage("settings.showAccountChooserOnLaunch") private var showAccountChooserOnLaunch: Bool = true
    @AppStorage("onboarding.didComplete") private var didCompleteOnboarding: Bool = false
    @AppStorage("onboarding.preferSkip") private var preferSkipOnboarding: Bool = false
    @AppStorage("onboarding.forceShowNextLaunch") private var forceShowOnboardingNextLaunch: Bool = false
    @AppStorage("onboarding.presentNow") private var presentOnboardingNow: Bool = false

    @State private var clearCacheOnLogout: Bool = false
    @State private var preferDarkMode: Bool = true

    var body: some View {
        #if os(tvOS)
        tvSettingsLayout
        #else
        Form {
            Section(header: Text("Account")) {
                HStack {
                    Text("Username")
                    Spacer()
                    Text(session.currentUser?.name ?? "Not signed in")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Server")
                    Spacer()
                    Text(session.serverURL.host ?? session.serverURL.absoluteString)
                        .foregroundColor(.secondary)
                }
                if let join = session.joinDate {
                    HStack {
                        Text("Member Since")
                        Spacer()
                        Text(join.formatted(date: .abbreviated, time: .omitted))
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink {
                    ManageAccountsView()
                } label: {
                    Label("Remembered Accounts", systemImage: "person.2.circle")
                }
            }

            Section(header: Text("App Settings")) {
                Toggle("Enable Dark Mode", isOn: $preferDarkMode)
                Toggle("Clear Cache on Logout", isOn: $clearCacheOnLogout)
                Toggle("Default to remembering accounts", isOn: $defaultRememberAccount)
                Toggle("Show account chooser on launch", isOn: $showAccountChooserOnLaunch)

            }

            Section(header: Text("Welcome Tour")) {
                Button {
                    // Present immediately (works even before login).
                    preferSkipOnboarding = false
                    didCompleteOnboarding = false
                    presentOnboardingNow = true
                } label: {
                    Label("Show welcome tour now", systemImage: "sparkles")
                }

                Toggle(isOn: Binding(
                    get: { forceShowOnboardingNextLaunch },
                    set: { newValue in
                        // If enabling, ensure it isn't considered skipped.
                        if newValue {
                            preferSkipOnboarding = false
                            didCompleteOnboarding = false
                        }
                        forceShowOnboardingNextLaunch = newValue
                    }
                )) {
                    Text("Show tour on next launch")
                }
            }

            Section(header: Text("About")) {
                Text("Brockbuster is a Jellyfin-powered client designed for a premium, cinema-first experience.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Settings")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
        #endif
    }

    #if os(tvOS)
    private var tvSettingsLayout: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.65), BrockbusterTheme.brockBlue.opacity(0.55)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(BrockbusterTheme.brockLight)
                        .padding(.top, 6)

                    MoreSectionCard(title: "Account") {
                        SettingsInfoRow(title: "Username", value: session.currentUser?.name ?? "Not signed in")
                        SettingsInfoRow(title: "Server", value: session.serverURL.host ?? session.serverURL.absoluteString)
                        if let join = session.joinDate {
                            SettingsInfoRow(title: "Member Since", value: join.formatted(date: .abbreviated, time: .omitted))
                        }

                        NavigationLink {
                            ManageAccountsView()
                        } label: {
                            MoreRow(title: "Remembered Accounts", systemImage: "person.2.circle")
                        }
                        .buttonStyle(.plain)
                        .bbTVFocusCard(cornerRadius: 18)
                    }

                    MoreSectionCard(title: "App Settings") {
                        SettingsToggleRow(title: "Enable Dark Mode", isOn: $preferDarkMode)
                        SettingsToggleRow(title: "Clear Cache on Logout", isOn: $clearCacheOnLogout)
                        SettingsToggleRow(title: "Default to remembering accounts", isOn: $defaultRememberAccount)
                        SettingsToggleRow(title: "Show account chooser on launch", isOn: $showAccountChooserOnLaunch)
                    }

                    MoreSectionCard(title: "Welcome Tour") {
                        Button {
                            // Present immediately.
                            preferSkipOnboarding = false
                            didCompleteOnboarding = false
                            presentOnboardingNow = true
                        } label: {
                            MoreRow(title: "Show welcome tour now", systemImage: "sparkles")
                        }
                        .buttonStyle(.plain)
                        .bbTVFocusCard(cornerRadius: 18)

                        SettingsToggleRow(title: "Show tour on next launch", isOn: Binding(
                            get: { forceShowOnboardingNextLaunch },
                            set: { newValue in
                                if newValue {
                                    preferSkipOnboarding = false
                                    didCompleteOnboarding = false
                                }
                                forceShowOnboardingNextLaunch = newValue
                            }
                        ))
                    }

                    MoreSectionCard(title: "About") {
                        Text("Brockbuster is a Jellyfin-powered client designed for a premium, cinema-first experience.")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))
                            .padding(.horizontal, 6)
                    }

                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 46)
                .padding(.bottom, 40)
                .frame(maxWidth: 1400, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Settings")
        .bbNavigationTitleInline()
    }
    #endif
}

#if os(tvOS)
private struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.70))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight)
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        // Give the row focus styling rather than the toggle's giant default.
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .bbTVFocusCard(cornerRadius: 18)
    }
}
#endif

#if DEBUG
struct MoreView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MoreView()
                .environmentObject(SessionStore())
                .environmentObject(AccountManager())
        }
    }
}
#endif
