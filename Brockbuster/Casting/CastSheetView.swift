import SwiftUI

struct CastSheetView: View {
    @EnvironmentObject private var castManager: CastManager
    @EnvironmentObject private var nowPlaying: NowPlayingManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingManualDLNAAdd: Bool = false
    @State private var manualDLNAURL: String = ""
    @State private var manualDLNAError: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Apple does not expose AirPlay routes as a list for custom UI.
                    // To make the UX feel like a normal list row, we overlay an invisible
                    // AVRoutePickerView across the entire row so the user can tap anywhere.
                    ZStack {
                        HStack(spacing: 12) {
                            Image(systemName: "airplayvideo")
                                .imageScale(.large)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AirPlay")
                                    .font(.headline)
                                Text("Tap to choose a device")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)

                        CastRoutePickerView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(0.02)
                            .accessibilityLabel("AirPlay")
                    }
                }

                if let connected = castManager.connection.connectedDevice {
                    Section("Connected") {
                        connectedRow(connected)
                    }
                }

                Section("Nearby Devices") {
                    providerDeviceRows(kind: .dlna)

                    Button {
                        manualDLNAURL = ""
                        manualDLNAError = nil
                        showingManualDLNAAdd = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add DLNA device by URL")
                                    .font(.headline)
                                Text("Use the device description (LOCATION) URL")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Show other providers as "coming soon" but do not imply nothing is supported.
                    comingSoonRow(kind: .googleCast)
                    comingSoonRow(kind: .roku)
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
            .sheet(isPresented: $showingManualDLNAAdd) {
                NavigationStack {
                    Form {
                        Section("Device Description URL") {
                            TextField("http://<ip>:<port>/description.xml", text: $manualDLNAURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.URL)
                        }

                        if let manualDLNAError {
                            Section {
                                Text(manualDLNAError)
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                            }
                        }

                        Section {
                            Button("Add Device") {
                                Task {
                                    do {
                                        try await castManager.addManualDLNA(descriptionURLString: manualDLNAURL)
                                        showingManualDLNAAdd = false
                                    } catch {
                                        await MainActor.run {
                                            manualDLNAError = (error as NSError).localizedDescription
                                        }
                                    }
                                }
                            }
                            .disabled(manualDLNAURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .navigationTitle("Add DLNA Device")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showingManualDLNAAdd = false }
                        }
                    }
                }
                .presentationDetents([.medium])
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
                    if kind == .dlna, castManager.manualDLNADevices.contains(where: { $0.id == device.id }) {
                        Button(role: .destructive) {
                            castManager.removeManualDLNA(device)
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
}
