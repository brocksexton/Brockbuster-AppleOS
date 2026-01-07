import Foundation
import Combine

/// Aggregates multiple cast providers behind a single, user-facing interface.
/// In v0.1.1 this ships with AirPlay (system route picker) plus placeholders
/// for Chromecast/Roku/Brockbuster receivers. As providers are integrated,
/// their discovered devices will automatically populate the casting sheet.
final class CastManager: ObservableObject {
    @Published private(set) var devices: [CastDevice] = []
    @Published private(set) var connection: CastConnectionState = .init()

    let providers: [CastProvider]

    private var cancellables: Set<AnyCancellable> = []
    private var devicesByProvider: [CastProviderKind: [CastDevice]] = [:]
    private var connectionByProvider: [CastProviderKind: CastConnectionState] = [:]

    init() {
        let dlna = DLNACastProvider()

        // Roku support is implemented natively via best-effort discovery + manual add.
        let roku = RokuCastProvider()

        // Chromecast support is implemented when the Google Cast SDK is present.
        // If the SDK is not linked, we fall back to a placeholder provider so the UI
        // can explain what to do.
        let google: CastProvider = GoogleCastProviderFactory.makeProvider()

        let brock = PlaceholderCastProvider(
            kind: .brockbusterReceiver,
            message: "Brockbuster enhanced casting will be added via receiver discovery on Apple TV and other targets."
        )

        // AirPlay is presented via the system route picker and is not represented as discoverable
        // devices here (Apple does not expose AirPlay devices as a list programmatically).

        self.providers = [dlna, google, roku, brock]
        bindProviders()
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
        devices = CastProviderKind.allCases
            .flatMap { devicesByProvider[$0] ?? [] }
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
}
