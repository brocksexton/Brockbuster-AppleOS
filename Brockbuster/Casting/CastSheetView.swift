import SwiftUI

struct CastSheetView: View {
    @EnvironmentObject private var castManager: CastManager
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingManualRokuAdd: Bool = false
    @State private var manualRokuHost: String = ""
    @State private var manualRokuError: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "airplayvideo")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AirPlay")
                                .font(.headline)
                            Text("Choose a device using the system picker")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        CastRoutePickerView()
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("AirPlay")
                    }
                }

                if let connected = castManager.connection.connectedDevice {
                    Section("Connected") {
                        connectedRow(connected)
                    }
                }

                Section("Chromecast") {
                    providerDeviceRows(kind: .googleCast)
                    if let message = placeholderMessage(for: .googleCast) {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Roku") {
                    providerDeviceRows(kind: .roku)
                    Button {
                        manualRokuHost = ""
                        manualRokuError = nil
                        showingManualRokuAdd = true
                    } label: {
                        Label("Add Roku by IP / Host", systemImage: "plus")
                    }
                    Text("Note: Many Roku devices support AirPlay and will work from the AirPlay picker. Native Roku casting requires a Roku receiver/channel; this list focuses on device discovery today.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Smart TVs (DLNA)") {
                    providerDeviceRows(kind: .dlna)
                }

                Section("Brockbuster") {
                    comingSoonRow(kind: .brockbusterReceiver)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Casting")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { castManager.startDiscovery() }
            .onDisappear { castManager.stopDiscovery() }
            .sheet(isPresented: $showingManualRokuAdd) {
                NavigationStack {
                    Form {
                        Section("Roku Address") {
                            TextField("192.168.0.25", text: $manualRokuHost)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.URL)
                            Text("Enter the Roku device IP or host on your local network. The app will use Roku ECP (http://<host>:8060).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let manualRokuError {
                            Section {
                                Text(manualRokuError)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .navigationTitle("Add Roku")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showingManualRokuAdd = false }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Add") {
                                addManualRoku()
                            }
                            .disabled(manualRokuHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func connectedRow(_ connected: CastDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: connected.provider.systemImageName)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connected.name)
                        .font(.headline)
                    Text(connected.detail ?? connected.provider.displayName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { castManager.disconnect() } label: { Text("Disconnect") }
            }

            if let payload = nowPlaying.makeCastPayload() {
                Button {
                    nowPlaying.pauseLocalPlaybackForCasting()
                    castManager.cast(payload)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play current item on \(connected.name)")
                    }
                }
            } else {
                Text("Start playback first, then cast from here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func providerDeviceRows(kind: CastProviderKind) -> some View {
        let devices = castManager.devices.filter { $0.provider == kind }

        if devices.isEmpty {
            // Chromecast uses an SDK; if it's not linked, show a static hint instead of a spinner.
            if kind == .googleCast, placeholderMessage(for: .googleCast) != nil {
                HStack(spacing: 12) {
                    Image(systemName: kind.systemImageName)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chromecast not enabled")
                            .font(.headline)
                        Text("Add the Google Cast SDK to discover Cast devices.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: kind.systemImageName)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Searching for \(kind.displayName)…")
                            .font(.headline)
                        Text("Make sure your device is on the same Wi‑Fi.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressView()
                }
            }
        } else {
            ForEach(devices) { device in
                Button {
                    castManager.connect(to: device)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.systemImageName)
                            .imageScale(.large)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.headline)
                            if let detail = device.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .contextMenu {
                    if kind == .roku, let roku = rokuProvider(), device.detail == "Manual" {
                        Button(role: .destructive) {
                            roku.removeManualRoku(device)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func comingSoonRow(kind: CastProviderKind) -> some View {
        if kind == .dlna || kind == .airPlay { EmptyView() } else {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImageName)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.headline)
                    Text("Support will be added in a future update")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .opacity(0.6)
        }
    }

    private func placeholderMessage(for kind: CastProviderKind) -> String? {
        guard let provider = castManager.providers.first(where: { $0.kind == kind }) else { return nil }
        if let placeholder = provider as? PlaceholderCastProvider {
            return placeholder.placeholderMessage
        }
        return nil
    }

    private func rokuProvider() -> RokuCastProvider? {
        castManager.providers.compactMap { $0 as? RokuCastProvider }.first
    }

    private func addManualRoku() {
        let host = manualRokuHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        guard let roku = rokuProvider() else {
            manualRokuError = "Roku provider not available."
            return
        }
        roku.addManualRoku(ipOrHost: host)
        showingManualRokuAdd = false
    }
}
