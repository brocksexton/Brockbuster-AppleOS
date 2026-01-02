import Foundation
import SwiftUI

@MainActor
final class FriendsViewModel: ObservableObject {

    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    @Published var pending: [BrockbusterAPI.FriendsPayload.FriendItem] = []
    @Published var friends: [BrockbusterAPI.FriendsPayload.FriendItem] = []

    func load(session: SessionStore) async {
        // SessionStore tracks the current Jellyfin session.
        // Use the same token/userId pair that the Jellyfin API client uses.
        guard let token = session.accessToken,
              let userId = session.currentUser?.id else {
            errorMessage = "Not logged in."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let payload = try await BrockbusterAPI.shared.fetchFriends(
                jellyfinToken: token,
                jellyfinUserId: userId
            )

            pending = payload.pending ?? []
            friends = payload.friends ?? []

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
