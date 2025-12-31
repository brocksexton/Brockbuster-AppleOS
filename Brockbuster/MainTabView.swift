import SwiftUI
import UIKit

/// The top-level view displayed after the user logs in.  It presents a tabbed interface
/// with placeholders for upcoming features (Friends, Server Health, Social) and the
/// existing Home tab that shows the user's media libraries.  Each tab is wrapped in
/// its own navigation view to allow for deep navigation (e.g. library detail views).
struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        TabView {
            NavigationView {
                HomeView()
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }

            NavigationView {
                MembershipCardView()
            }
            .tabItem {
                Image(systemName: "wallet.pass")
                Text("Member")
            }

            NavigationView {
                MoreView()
            }
            .tabItem {
                Image(systemName: "ellipsis.circle")
                Text("More")
            }
        }
        .tint(BrockbusterTheme.brockGold)
        .onAppear {
            // Customize tab bar appearance on iOS to improve contrast for unselected items
            #if os(iOS)
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(BrockbusterTheme.brockDark)
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(BrockbusterTheme.brockGold)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(BrockbusterTheme.brockGold)]
            // Light colour for unselected icons and labels
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor(BrockbusterTheme.brockLight).withAlphaComponent(0.7)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(BrockbusterTheme.brockLight).withAlphaComponent(0.7)]
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
            #endif
        }
    }
}

/// Placeholder view for the Friends tab.  This will eventually show a list of
/// friends and their profiles from the secondary project.  For now it displays a
/// message indicating the feature is under construction.
struct FriendsTab: View {
    var body: some View {
        ZStack {
            // Slightly lighter gradient for improved contrast
            LinearGradient(gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.6), BrockbusterTheme.brockBlue.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "person.2.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(BrockbusterTheme.brockGold)
                Text("Friends List Coming Soon")
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)
                Text("Connect with your friends and see what they're watching.")
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Friends")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Placeholder view for the Server Health tab.  This tab will show status
/// information about the Jellyfin server such as CPU usage, memory and active
/// streams.  The view currently displays a placeholder message.
struct ServerHealthTab: View {
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.6), BrockbusterTheme.brockBlue.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "waveform.path.ecg")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(BrockbusterTheme.brockGold)
                Text("Server Health Coming Soon")
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)
                Text("Monitor your server's status and performance here.")
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Server")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Placeholder view for the Social tab.  This tab will eventually allow users to
/// share reviews and thoughts about media with friends and family.  Currently it
/// displays a friendly placeholder message.
struct SocialTab: View {
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.6), BrockbusterTheme.brockBlue.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "quote.bubble.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(BrockbusterTheme.brockGold)
                Text("Social Feed Coming Soon")
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)
                Text("Share your thoughts on movies and shows with friends.")
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Social")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#if DEBUG
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(SessionStore())
    }
}
#endif