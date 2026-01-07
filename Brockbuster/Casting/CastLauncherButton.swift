import SwiftUI

struct CastLauncherButton: View {
    @EnvironmentObject private var castManager: CastManager
    var size: CGFloat = 40

    @State private var showingSheet: Bool = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            Image(systemName: castManager.connection.isConnected ? "airplayvideo.circle.fill" : "airplayvideo")
                .font(.system(size: size * 0.52, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Casting")
        .sheet(isPresented: $showingSheet) {
            CastSheetView()
                .environmentObject(castManager)
        }
    }
}
