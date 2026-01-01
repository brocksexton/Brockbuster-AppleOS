import Foundation
import SwiftUI

/// Manages remembered Jellyfin accounts for quick sign-in.
///
/// - Account metadata is stored in UserDefaults.
/// - Access tokens are stored in Keychain.
@MainActor
final class AccountManager: ObservableObject {
    struct SavedAccount: Codable, Identifiable, Hashable {
        var id: UUID
        var serverURLString: String
        var userId: String
        var username: String
        var displayName: String?
        var remembered: Bool
        var lastUsedAt: Date
        var memberSince: Date?

        var serverURL: URL? { URL(string: serverURLString) }
    }

    private struct Keys {
        static let accounts = "AccountManager.accounts"
        static let lastSelectedAccountId = "AccountManager.lastSelectedAccountId"
    }

    @Published private(set) var accounts: [SavedAccount] = []

    init() {
        load()
    }

    var rememberedAccounts: [SavedAccount] {
        accounts
            .filter { $0.remembered }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    var hasRememberedAccounts: Bool {
        !rememberedAccounts.isEmpty
    }

    func token(for account: SavedAccount) -> String? {
        let key = tokenKey(for: account.id)
        guard let data = try? KeychainHelper.get(account: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func upsertAccount(
        serverURL: URL,
        user: JellyfinUser,
        accessToken: String,
        remembered: Bool,
        memberSince: Date?
    ) {
        let now = Date()
        // Use stable identity: (serverURL + userId) to avoid duplicates.
        if let idx = accounts.firstIndex(where: { $0.serverURLString == serverURL.absoluteString && $0.userId == user.id }) {
            accounts[idx].username = user.name
            accounts[idx].displayName = user.name
            accounts[idx].remembered = remembered
            accounts[idx].lastUsedAt = now
            if accounts[idx].memberSince == nil {
                accounts[idx].memberSince = memberSince
            }
            persistToken(accessToken, for: accounts[idx].id)
            save()
            setLastSelected(accounts[idx].id)
            return
        }

        let new = SavedAccount(
            id: UUID(),
            serverURLString: serverURL.absoluteString,
            userId: user.id,
            username: user.name,
            displayName: user.name,
            remembered: remembered,
            lastUsedAt: now,
            memberSince: memberSince
        )
        accounts.append(new)
        persistToken(accessToken, for: new.id)
        save()
        setLastSelected(new.id)
    }

    func setRemembered(_ remembered: Bool, for accountId: UUID) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountId }) else { return }
        accounts[idx].remembered = remembered
        save()
    }

    func removeAccount(_ accountId: UUID) {
        if let idx = accounts.firstIndex(where: { $0.id == accountId }) {
            let removed = accounts.remove(at: idx)
            try? KeychainHelper.delete(account: tokenKey(for: removed.id))
            save()
        }
    }

    func lastSelectedAccountId() -> UUID? {
        if let raw = UserDefaults.standard.string(forKey: Keys.lastSelectedAccountId) {
            return UUID(uuidString: raw)
        }
        return nil
    }

    func setLastSelected(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: Keys.lastSelectedAccountId)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Keys.accounts) else {
            accounts = []
            return
        }
        do {
            accounts = try JSONDecoder().decode([SavedAccount].self, from: data)
        } catch {
            accounts = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(accounts)
            UserDefaults.standard.set(data, forKey: Keys.accounts)
        } catch {
            // ignore
        }
        objectWillChange.send()
    }

    private func persistToken(_ token: String, for id: UUID) {
        let key = tokenKey(for: id)
        if let data = token.data(using: .utf8) {
            try? KeychainHelper.set(data, account: key)
        }
    }

    private func tokenKey(for id: UUID) -> String {
        "brockbuster.jellyfin.token.\(id.uuidString)"
    }
}

