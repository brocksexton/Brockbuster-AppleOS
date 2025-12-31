import SwiftUI

/// A simple landing screen displayed after successful authentication.  It greets
/// the user and provides basic navigation actions (log out, change server).
/// Future development would populate this view with the user's media library,
/// continue watching list and recommendations.
struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Background gradient (further lightened for improved readability)
            LinearGradient(gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.6), BrockbusterTheme.brockBlue.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                        // Profile and greeting
                        HStack(alignment: .center, spacing: 16) {
                            if let url = session.userProfileImageURL(maxWidth: 120) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 60, height: 60)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 60, height: 60)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(BrockbusterTheme.brockGold, lineWidth: 2))
                                    case .failure:
                                        Image(systemName: "person.crop.circle.fill")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 60, height: 60)
                                            .foregroundColor(BrockbusterTheme.brockGold)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                if let user = session.currentUser {
                                    Text("Welcome, \(user.name)")
                                        .font(BrockbusterTheme.Fonts.title)
                                        .foregroundColor(BrockbusterTheme.brockLight)
                                }
                                Text("Browse your libraries below")
                                    .font(BrockbusterTheme.Fonts.body)
                                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding(.bottom, 8)
                        // Libraries section
                        if session.isFetchingLibraries {
                            HStack {
                                ProgressView("Loading Libraries…")
                                    .progressViewStyle(CircularProgressViewStyle(tint: BrockbusterTheme.brockGold))
                                    .foregroundColor(BrockbusterTheme.brockGold)
                                Spacer()
                            }
                        } else {
                            if !session.libraries.isEmpty {
                                ForEach(session.libraries) { library in
                                    NavigationLink(destination: LibraryDetailView(library: library).environmentObject(session)) {
                                        HStack(spacing: 16) {
                                            if let imageURL = session.libraryImageURL(for: library, maxWidth: 200) {
                                                AsyncImage(url: imageURL) { phase in
                                                    switch phase {
                                                    case .empty:
                                                        Rectangle()
                                                            .fill(BrockbusterTheme.brockDark.opacity(0.3))
                                                            .frame(width: 120, height: 70)
                                                            .cornerRadius(12)
                                                    case .success(let image):
                                                        image
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 120, height: 70)
                                                            .clipped()
                                                            .cornerRadius(12)
                                                    case .failure:
                                                        Rectangle()
                                                            .fill(BrockbusterTheme.brockDark.opacity(0.3))
                                                            .frame(width: 120, height: 70)
                                                            .overlay(Image(systemName: "film.fill").foregroundColor(BrockbusterTheme.brockGold))
                                                            .cornerRadius(12)
                                                    @unknown default:
                                                        EmptyView()
                                                    }
                                                }
                                            }
                                            VStack(alignment: .leading) {
                                                Text(library.name)
                                                    .font(BrockbusterTheme.Fonts.title)
                                                    .foregroundColor(BrockbusterTheme.brockLight)
                                                Text("Library")
                                                    .font(BrockbusterTheme.Fonts.body)
                                                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.7))
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(BrockbusterTheme.brockGold)
                                        }
                                        .padding()
                                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(BrockbusterTheme.brockBlue.opacity(0.4), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            } else if session.currentUser != nil {
                                Text("No libraries found.")
                                    .foregroundColor(BrockbusterTheme.brockLight)
                            }
                        }
                        // Actions
                        HStack {
                            Button(action: session.logout) {
                                Text("Log Out")
                                    .font(BrockbusterTheme.Fonts.body.weight(.bold))
                                    .foregroundColor(BrockbusterTheme.brockDark)
                            }
                            .buttonStyle(BrockbusterTheme.TicketButtonStyle())
                            Button(action: session.resetServer) {
                                Text("Change Server")
                                    .font(BrockbusterTheme.Fonts.body.weight(.bold))
                                    .foregroundColor(BrockbusterTheme.brockDark)
                            }
                            .buttonStyle(BrockbusterTheme.TicketButtonStyle())
                        }
                        .padding(.top, 16)
                        // Error message
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.footnote)
                        }
                }
                .padding()
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Fetch libraries on first load
            if session.isLoggedIn && session.libraries.isEmpty {
                do {
                    try await session.fetchLibraries()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
