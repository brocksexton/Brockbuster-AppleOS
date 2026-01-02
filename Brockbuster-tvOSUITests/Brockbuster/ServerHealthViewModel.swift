import Foundation

@MainActor
final class ServerHealthViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var health: BrockbusterAPI.HealthV2Response?

    func refresh(jellyfinToken: String?, jellyfinUserId: String?) async {
        guard let jellyfinToken, !jellyfinToken.isEmpty,
              let jellyfinUserId, !jellyfinUserId.isEmpty else {
            errorMessage = BrockbusterAPI.APIError.notAuthenticated.localizedDescription
            health = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await BrockbusterAPI.shared.fetchHealthV2(
                jellyfinToken: jellyfinToken,
                jellyfinUserId: jellyfinUserId
            )
            health = result
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            health = nil
        }
    }
}
