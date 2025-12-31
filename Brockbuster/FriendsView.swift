import SwiftUI

struct FriendsView: View {

    @EnvironmentObject var session: SessionStore
    @StateObject private var vm = FriendsViewModel()

    var body: some View {
        List {

            if let error = vm.errorMessage {
                GlassCard {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                }
            }

            if vm.isLoading {
                GlassCard {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading friends…")
                            .font(BrockbusterTheme.Fonts.body)
                    }
                }
            }

            if !vm.pending.isEmpty {
                Section("Incoming / Pending") {
                    ForEach(vm.pending, id: \.friendshipId) { item in
                        FriendRow(item: item)
                    }
                }
            } else {
                Section("Incoming / Pending") {
                    Text("No incoming requests.")
                        .font(BrockbusterTheme.Fonts.body)
                        .foregroundColor(.secondary)
                }
            }

            if !vm.friends.isEmpty {
                Section("Friends") {
                    ForEach(vm.friends, id: \.friendshipId) { item in
                        FriendRow(item: item)
                    }
                }
            } else {
                Section("Friends") {
                    Text("No friends yet.")
                        .font(BrockbusterTheme.Fonts.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Friends")
        .task {
            await vm.load(session: session)
        }
    }
}
