import SwiftUI

struct FriendRow: View {
    let item: BrockbusterAPI.FriendsPayload.FriendItem

    var body: some View {
        let displayName = item.user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (displayName?.isEmpty == false) ? displayName! : "Unknown"
        let status = (item.status ?? "unknown").capitalized

        HStack(spacing: 12) {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading) {
                Text(name)
                    .font(BrockbusterTheme.Fonts.body)

                Text(status)
                    .font(BrockbusterTheme.Fonts.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}
