import SwiftUI

/// Allows the user to manage remembered accounts stored on this device.
struct ManageAccountsView: View {
    @EnvironmentObject private var accounts: AccountManager

    var body: some View {
        List {
            Section("Remembered Accounts") {
                if accounts.accounts.isEmpty {
                    ContentUnavailableView("No accounts saved", systemImage: "person.crop.circle.badge.xmark", description: Text("Sign in with 'Remember this account' enabled to save an account."))
                } else {
                    ForEach(accounts.accounts) { acct in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(acct.displayName ?? acct.username)
                                    .font(.headline)
                                Text(acct.serverURL?.host ?? acct.serverURLString)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { acct.remembered },
                                set: { newValue in
                                    accounts.setRemembered(newValue, for: acct.id)
                                }
                            ))
                            .labelsHidden()
                        }
                        #if !os(tvOS)
                        .swipeActions {
                            Button(role: .destructive) {
                                accounts.removeAccount(acct.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        #endif
                    }
                }
            }

            Section {
                Text("Access tokens are stored securely in Keychain. Turning off a toggle hides the account from the chooser screen, but keeps it available until you remove it.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Accounts")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
    }
}

#if DEBUG
struct ManageAccountsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ManageAccountsView()
                .environmentObject(AccountManager())
        }
    }
}
#endif
