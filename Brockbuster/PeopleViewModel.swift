//
//  PeopleViewModel.swift
//  Brockbuster
//

import Foundation

@MainActor
final class PeopleViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    @Published var query: String = ""
    @Published var results: [BrockbusterAPI.PeoplePayload.Person] = []

    func refresh(session: SessionStore, reset: Bool = true) async {
        guard let token = session.accessToken,
              let userId = session.currentUser?.id else {
            errorMessage = "Not logged in."
            results = []
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let payload = try await BrockbusterAPI.shared.fetchPeople(
                jellyfinToken: token,
                jellyfinUserId: userId,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : query,
                limit: 24,
                offset: 0
            )
            results = payload.results ?? []
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }

        isLoading = false
    }
}
