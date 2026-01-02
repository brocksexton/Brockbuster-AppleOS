import SwiftUI

/// A consolidated list of secondary screens that don't need their own bottom-tab.
/// This menu is intended to be extensible as Brockbuster grows (accounts, friends,
/// stats/health, settings, etc.).
struct MoreView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showingLogoutConfirm = false

    var body: some View {
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
    }
}

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

    @State private var clearCacheOnLogout: Bool = false
    @State private var preferDarkMode: Bool = true

    var body: some View {
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

                Button {
                    // Reset the tour flags so it will appear on next launch.
                    didCompleteOnboarding = false
                    preferSkipOnboarding = false
                } label: {
                    Label("Show welcome tour on next launch", systemImage: "sparkles")
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
    }
}

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
