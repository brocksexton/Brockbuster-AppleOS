import Foundation
import Combine

protocol CastProvider: AnyObject {
    var kind: CastProviderKind { get }
    var displayName: String { get }

    var devicesPublisher: AnyPublisher<[CastDevice], Never> { get }
    var connectionPublisher: AnyPublisher<CastConnectionState, Never> { get }

    func startDiscovery()
    func stopDiscovery()

    func connect(to device: CastDevice)
    func disconnect()

    /// Ask the provider to start playback of the given media on the connected device.
    /// Providers that cannot accept remote URLs (or are not implemented yet) should no-op.
    func loadMedia(_ payload: CastMediaPayload)
}

/// A lightweight base implementation you can subclass for specific providers.
class BaseCastProvider: CastProvider {
    let kind: CastProviderKind
    var displayName: String { kind.displayName }

    @Published private var devices: [CastDevice] = []
    @Published private var connection: CastConnectionState = .init()

    var devicesPublisher: AnyPublisher<[CastDevice], Never> { $devices.eraseToAnyPublisher() }
    var connectionPublisher: AnyPublisher<CastConnectionState, Never> { $connection.eraseToAnyPublisher() }

    init(kind: CastProviderKind) {
        self.kind = kind
    }

    func startDiscovery() { /* override */ }
    func stopDiscovery() { /* override */ }

    func connect(to device: CastDevice) {
        // Default behaviour: mark connected to selected device.
        connection.connectedDevice = device
    }

    func disconnect() {
        connection.connectedDevice = nil
    }

    func loadMedia(_ payload: CastMediaPayload) {
        // Default: not supported.
    }

    // MARK: - Protected helpers

    func setDevices(_ devices: [CastDevice]) {
        self.devices = devices
    }

    func setConnectedDevice(_ device: CastDevice?) {
        connection.connectedDevice = device
    }
}

/// Placeholder provider that keeps the UI consistent until a real provider is added.
final class PlaceholderCastProvider: BaseCastProvider {
    private let message: String

    init(kind: CastProviderKind, message: String) {
        self.message = message
        super.init(kind: kind)
    }

    override func startDiscovery() {
        // No-op: discovery will be implemented when integrating the provider SDK/protocol.
        setDevices([])
    }

    override func stopDiscovery() {}

    var placeholderMessage: String { message }
}
