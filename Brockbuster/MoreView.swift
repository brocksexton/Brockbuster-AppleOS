import SwiftUI

/// A consolidated list of secondary screens that don't need their own tab.  This
/// view is shown under the "More" tab to avoid cluttering the main tab bar.  Each
/// row navigates to a placeholder view for future features (Friends, Server
/// Health, Social, Settings).  Additional entries can be added as new features
/// are developed.
import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        List {
            NavigationLink(destination: FriendsView()) {
                Label("Friends", systemImage: "person.2.fill")
            }

            NavigationLink(destination: PeopleView()) {
                Label("People", systemImage: "person.crop.square")
            }

            NavigationLink(destination: ServerHealthTab()) {
                Label("Server Health", systemImage: "waveform.path.ecg")
            }

            NavigationLink(destination: SocialTab()) {
                Label("Social Feed", systemImage: "quote.bubble.fill")
            }

            NavigationLink(destination: SettingsTab()) {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .navigationTitle("More")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}

/// Placeholder settings view to demonstrate adding additional pages.  You can
/// customize this with real settings for the app such as theme, login info or
/// cache management.
struct SettingsTab: View {
    var body: some View {
        Form {
            Section(header: Text("Account")) {
                Text("Username: TBD")
                Text("Server: vcr.brockbuster.lol")
            }
            Section(header: Text("App Settings")) {
                Toggle("Enable Dark Mode", isOn: .constant(true))
                Toggle("Clear Cache on Logout", isOn: .constant(false))
            }
        }
        .navigationTitle("Settings")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#if DEBUG
struct MoreView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MoreView()
        }
    }
}
#endif
