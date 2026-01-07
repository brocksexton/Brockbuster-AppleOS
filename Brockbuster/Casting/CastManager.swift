import Foundation
import Combine

/// Aggregates multiple cast providers behind a single, user-facing interface.
/// In v0.1.1 this ships with AirPlay (system route picker) plus placeholders
/// for Chromecast/Roku/Brockbuster receivers. As providers are integrated,
/// their discovered devices will automatically populate the casting sheet.
final class CastManager: ObservableObject {
    @Published private(set) var devices: [CastDevice] = []
    @Published private(set) var connection: CastConnectionState = .init()

    /// Manually added DLNA devices (used when multicast discovery is unavailable).
    @Published private(set) var manualDLNADevices: [CastDevice] = []

    let providers: [CastProvider]

    private let dlnaProvider: DLNACastProvider

    private var cancellables: Set<AnyCancellable> = []
    private var devicesByProvider: [CastProviderKind: [CastDevice]] = [:]
    private var connectionByProvider: [CastProviderKind: CastConnectionState] = [:]

    private let manualDLNAKey = "casting.manualDLNADevices.v1"

    init() {
        let dlna = DLNACastProvider()
        self.dlnaProvider = dlna

        // AirPlay is presented via the system route picker and is not represented as discoverable
        // devices here (Apple does not expose AirPlay devices as a list programmatically).
        let google = PlaceholderCastProvider(
            kind: .googleCast,
            message: "Chromecast support will be added via Google Cast SDK."
        )
        let roku = PlaceholderCastProvider(
            kind: .roku,
            message: "Roku support will be added via Roku discovery (SSDP) + ECP control."
        )
        let brock = PlaceholderCastProvider(
            kind: .brockbusterReceiver,
            message: "Brockbuster enhanced casting will be added via receiver discovery on Apple TV and other targets."
        )

        self.providers = [dlna, google, roku, brock]
        self.manualDLNADevices = Self.loadManualDLNA(key: manualDLNAKey)
        bindProviders()
        recomputeDevices()
    }

    private func bindProviders() {
        for provider in providers {
            provider.devicesPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] devices in
                    guard let self else { return }
                    self.devicesByProvider[provider.kind] = devices
                    self.recomputeDevices()
                }
                .store(in: &cancellables)

            provider.connectionPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self else { return }
                    self.connectionByProvider[provider.kind] = state
                    self.recomputeConnection()
                }
                .store(in: &cancellables)
        }
    }

    private func recomputeDevices() {
        var merged: [CastDevice] = CastProviderKind.allCases
            .flatMap { devicesByProvider[$0] ?? [] }

        // Merge in manually added DLNA devices (dedupe by id).
        for d in manualDLNADevices {
            if !merged.contains(where: { $0.id == d.id }) {
                merged.append(d)
            }
        }

        // Stable sort for nicer UX.
        devices = merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func recomputeConnection() {
        let connected = CastProviderKind.allCases
            .compactMap { connectionByProvider[$0]?.connectedDevice }
            .first

        connection.connectedDevice = connected
    }

    func startDiscovery() {
        providers.forEach { $0.startDiscovery() }
    }

    func stopDiscovery() {
        providers.forEach { $0.stopDiscovery() }
    }

    func connect(to device: CastDevice) {
        guard let provider = providers.first(where: { $0.kind == device.provider }) else { return }
        provider.connect(to: device)
    }

    func disconnect() {
        providers.forEach { $0.disconnect() }
    }

    func cast(_ payload: CastMediaPayload) {
        guard let connected = connection.connectedDevice else { return }
        guard let provider = providers.first(where: { $0.kind == connected.provider }) else { return }
        provider.loadMedia(payload)
    }

    /// Returns true once any non-AirPlay provider has discovered at least one device.
    /// AirPlay is always available via the system route picker.
    func hasRemoteTargets() -> Bool {
        return !devices.isEmpty
    }

    // MARK: - Manual DLNA

    @MainActor
    func addManualDLNA(descriptionURLString: String) async throws {
        guard let url = URL(string: descriptionURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "DLNA", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]) 
        }

        let device = try await dlnaProvider.resolveDevice(fromDescriptionURL: url)
        if !manualDLNADevices.contains(where: { $0.id == device.id }) {
            manualDLNADevices.append(device)
            Self.saveManualDLNA(manualDLNADevices, key: manualDLNAKey)
            recomputeDevices()
        }
    }

    @MainActor
    func removeManualDLNA(_ device: CastDevice) {
        manualDLNADevices.removeAll(where: { $0.id == device.id })
        Self.saveManualDLNA(manualDLNADevices, key: manualDLNAKey)
        recomputeDevices()
    }

    private static func loadManualDLNA(key: String) -> [CastDevice] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CastDevice].self, from: data)) ?? []
    }

    private static func saveManualDLNA(_ devices: [CastDevice], key: String) {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
