import Foundation

#if canImport(GoogleCast)
import GoogleCast

/// Chromecast / Google Cast provider.
///
/// This implementation uses the Google Cast SDK for discovery, connection and
/// basic media loading via the Default Media Receiver.
///
/// Requirements:
/// - Link the Google Cast SDK to the iOS target.
/// - Add the "Local Network" privacy usage string to Info.plist (already present
///   in most modern projects that do discovery).
/// - Provide a valid receiver ID if you later move to a custom receiver.
final class GoogleCastProvider: BaseCastProvider, GCKDiscoveryManagerListener, GCKSessionManagerListener {
    private let castContext: GCKCastContext

    override init(kind: CastProviderKind = .googleCast) {
        self.castContext = GCKCastContext.sharedInstance()
        super.init(kind: kind)
    }

    override func startDiscovery() {
        let discovery = castContext.discoveryManager
        discovery.add(self)
        discovery.startDiscovery()

        let sessionManager = castContext.sessionManager
        sessionManager.add(self)

        refreshDevices()
        refreshConnection()
    }

    override func stopDiscovery() {
        castContext.discoveryManager.remove(self)
        castContext.discoveryManager.stopDiscovery()
        castContext.sessionManager.remove(self)
    }

    override func connect(to device: CastDevice) {
        guard let target = findDevice(by: device.id) else {
            return
        }
        castContext.sessionManager.startSession(with: target)
    }

    override func disconnect() {
        castContext.sessionManager.endSessionAndStopCasting(true)
        setConnectedDevice(nil)
    }

    override func loadMedia(_ payload: CastMediaPayload) {
        guard let session = castContext.sessionManager.currentCastSession else { return }
        guard let mediaClient = session.remoteMediaClient else { return }

        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(payload.title, forKey: kGCKMetadataKeyTitle)
        if let subtitle = payload.subtitle {
            metadata.setString(subtitle, forKey: kGCKMetadataKeySubtitle)
        }
        if let imageURL = payload.imageURL {
            metadata.addImage(GCKImage(url: imageURL, width: 480, height: 720))
        }

        let mediaInfoBuilder = GCKMediaInformationBuilder(contentURL: payload.url)
        mediaInfoBuilder.streamType = .buffered
        mediaInfoBuilder.contentType = payload.contentType ?? "video/mp4"
        mediaInfoBuilder.metadata = metadata

        let request = mediaClient.loadMedia(mediaInfoBuilder.build())
        request.delegate = nil
    }

    // MARK: - GCKDiscoveryManagerListener

    func discoveryManager(_ discoveryManager: GCKDiscoveryManager, didInsert device: GCKDevice, at index: UInt) {
        refreshDevices()
    }

    func discoveryManager(_ discoveryManager: GCKDiscoveryManager, didUpdate device: GCKDevice, at index: UInt) {
        refreshDevices()
    }

    func discoveryManager(_ discoveryManager: GCKDiscoveryManager, didRemove device: GCKDevice, at index: UInt) {
        refreshDevices()
    }

    // MARK: - GCKSessionManagerListener

    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        refreshConnection()
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
        refreshConnection()
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        refreshConnection()
    }

    // MARK: - Helpers

    private func refreshDevices() {
        let devices = castContext.discoveryManager.devices
        let mapped: [CastDevice] = devices.map { d in
            CastDevice(id: d.deviceID, name: d.friendlyName ?? "Chromecast", provider: .googleCast, detail: d.modelName)
        }
        setDevices(mapped)
    }

    private func refreshConnection() {
        if let session = castContext.sessionManager.currentCastSession,
           let device = session.device {
            let d = CastDevice(id: device.deviceID, name: device.friendlyName ?? "Chromecast", provider: .googleCast, detail: device.modelName)
            setConnectedDevice(d)
        } else {
            setConnectedDevice(nil)
        }
    }

    private func findDevice(by id: String) -> GCKDevice? {
        castContext.discoveryManager.devices.first(where: { $0.deviceID == id })
    }
}

#endif

/// Factory used by CastManager so the project compiles even when the Google Cast SDK
/// is not linked.
enum GoogleCastProviderFactory {
    static func makeProvider() -> CastProvider {
        #if canImport(GoogleCast)
        return GoogleCastProvider()
        #else
        return PlaceholderCastProvider(
            kind: .googleCast,
            message: "Chromecast support requires adding the Google Cast SDK to the iOS target. Once linked, nearby Cast devices will appear here."
        )
        #endif
    }
}
