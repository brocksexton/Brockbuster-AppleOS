import SwiftUI

/// Displays a Brockbuster membership card with the user's name, membership ID and
/// membership duration.  This view also includes a placeholder "Add to Wallet"
/// button so users can eventually add their card to Apple Wallet.  Statistics
/// such as movies and TV shows watched can be shown once available.
struct MembershipCardView: View {
    @EnvironmentObject private var session: SessionStore
    
    var body: some View {
        ZStack {
            // Lightened gradient for better contrast on stats card
            LinearGradient(gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.6), BrockbusterTheme.brockBlue.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 32) {
                // Card representation including stats
                ZStack {
                    // Card background with subtle gradient and corner radius
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [BrockbusterTheme.brockBlue, BrockbusterTheme.brockDark]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 6)
                    VStack(alignment: .leading, spacing: 16) {
                        // Top row: profile picture and logo
                        HStack {
                            if let user = session.currentUser, let profileURL = session.userProfileImageURL(maxWidth: 200) {
                                // User profile picture
                                AsyncImage(url: profileURL) { phase in
                                    switch phase {
                                    case .empty:
                                        Circle().fill(BrockbusterTheme.brockDark.opacity(0.3))
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    case .failure:
                                        Circle().fill(BrockbusterTheme.brockDark.opacity(0.3)).overlay(Image(systemName: "person.fill").foregroundColor(BrockbusterTheme.brockGold))
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(BrockbusterTheme.brockGold, lineWidth: 2))
                            }
                            Spacer()
                            // Brockbuster logo at top right
                            Image("logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 32)
                        }
                        // User info and membership details
                        if let user = session.currentUser {
                            Text(user.name)
                                .font(BrockbusterTheme.Fonts.title.weight(.bold))
                                .foregroundColor(BrockbusterTheme.brockLight)
                            Text("Member ID: \(user.id.prefix(6))…")
                                .font(BrockbusterTheme.Fonts.body)
                                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.85))
                            Text(session.membershipDurationString())
                                .font(BrockbusterTheme.Fonts.body)
                                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.85))
                        }
                        Spacer()
                        // Stats section
                        Text("Your Stats")
                            .font(BrockbusterTheme.Fonts.title)
                            .foregroundColor(BrockbusterTheme.brockLight)
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Movies Watched")
                                    .font(BrockbusterTheme.Fonts.body)
                                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                                Text("—")
                                    .font(BrockbusterTheme.Fonts.title)
                                    .foregroundColor(BrockbusterTheme.brockGold)
                            }
                            Spacer()
                            VStack(alignment: .leading) {
                                Text("Shows Watched")
                                    .font(BrockbusterTheme.Fonts.body)
                                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                                Text("—")
                                    .font(BrockbusterTheme.Fonts.title)
                                    .foregroundColor(BrockbusterTheme.brockGold)
                            }
                            Spacer()
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: 350)
                // Add to wallet placeholder button
                Button(action: addToWallet) {
                    HStack {
                        Image(systemName: "wallet.pass.fill")
                        Text("Add to Wallet")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BrockbusterTheme.TicketButtonStyle())
                .frame(maxWidth: 350)
            }
            .padding()
        }
        .navigationTitle("Membership Card")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
    }
    
    /// Placeholder action for adding the membership card to Apple Wallet.  In a full
    /// implementation this would load a .pkpass file and present a PKAddPassesViewController.
    private func addToWallet() {
        // TODO: Integrate PassKit support here with a valid pass file
        print("Add to Wallet tapped")
    }
}

#if DEBUG
struct MembershipCardView_Previews: PreviewProvider {
    static var previews: some View {
        MembershipCardView()
            .environmentObject(SessionStore())
    }
}
#endif