import Foundation

/// Roku device support.
///
/// Practical constraints:
/// - Many Roku devices already show up via AirPlay if AirPlay 2 is enabled.
/// - "Real" Roku casting typically requires a Roku channel/receiver.
///
/// This provider still adds value by:
/// - Discovering Roku devices (best-effort) via SSDP so users see them in the Cast sheet.
/// - Allowing manual add by IP for networks where SSDP is blocked.
/// - Establishing a connection state so the rest of the UI can behave consistently.
///
/// In a future version, `loadMedia(_:)` can launch a Brockbuster Roku channel and
/// pass a payload (or token) to start playback.
final class RokuCastProvider: BaseCastProvider {
    private let discovery = SSDPDiscovery()
    private var discoveryTask: Task<Void, Never>?

    /// Persist manually added Roku targets.
    private let manualStoreKey = "casting.manualRokuTargets"

    override init(kind: CastProviderKind = .roku) {
        super.init(kind: kind)
        setDevices(loadManualTargets())
    }

    override func startDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = Task { [weak self] in
            guard let self else { return }

            // Best-effort: Roku ECP over SSDP typically advertises `roku:ecp`.
            // If multicast discovery is restricted, this may return no results.
            let responses = await discovery.search(st: "roku:ecp", timeout: 2.0)
            let discovered = await resolveRokuDevices(from: responses)

            // Merge discovered + manual
            let manual = loadManualTargets()
            let merged = mergeDevices(primary: discovered, secondary: manual)

            await MainActor.run {
                self.setDevices(merged)
            }
        }
    }

    override func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    override func connect(to device: CastDevice) {
        super.connect(to: device)
    }

    override func disconnect() {
        super.disconnect()
    }

    override func loadMedia(_ payload: CastMediaPayload) {
        // Not implemented yet.
        // Roku needs a receiver/channel to accept our payload.
        // We keep this method so the UI can call it uniformly.
        print("Roku casting is not yet implemented (requires a Roku receiver/channel).")
    }

    // MARK: - Manual targets

    func addManualRoku(ipOrHost: String) {
        let host = ipOrHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }

        // Roku ECP default port is 8060.
        let url = URL(string: "http://\(host):8060")
        let name = host
        let device = CastDevice(id: url?.absoluteString ?? host, name: name, provider: .roku, detail: "Manual")

        var manual = loadManualTargets()
        if !manual.contains(device) {
            manual.append(device)
            saveManualTargets(manual)
        }

        // Refresh list
        startDiscovery()
    }

    func removeManualRoku(_ device: CastDevice) {
        var manual = loadManualTargets()
        manual.removeAll { $0.id == device.id }
        saveManualTargets(manual)

        // Refresh list
        startDiscovery()
    }

    private func loadManualTargets() -> [CastDevice] {
        guard let data = UserDefaults.standard.data(forKey: manualStoreKey) else { return [] }
        guard let decoded = try? JSONDecoder().decode([ManualTarget].self, from: data) else { return [] }
        return decoded.map { CastDevice(id: $0.id, name: $0.name, provider: .roku, detail: "Manual") }
    }

    private func saveManualTargets(_ devices: [CastDevice]) {
        let payload = devices.map { ManualTarget(id: $0.id, name: $0.name) }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: manualStoreKey)
    }

    private struct ManualTarget: Codable {
        let id: String
        let name: String
    }

    // MARK: - Device resolution

    private func resolveRokuDevices(from responses: [SSDPDiscovery.Response]) async -> [CastDevice] {
        var out: [CastDevice] = []

        for r in responses {
            guard let location = r.location else { continue }

            // Most Roku SSDP responses include LOCATION pointing to device-desc.
            // We'll use it as the stable identifier.
            let name = r.server ?? "Roku"
            out.append(CastDevice(id: location.absoluteString, name: name, provider: .roku, detail: "Discovered"))
        }

        // De-dup
        var seen: Set<String> = []
        return out.filter { seen.insert($0.id).inserted }
    }

    private func mergeDevices(primary: [CastDevice], secondary: [CastDevice]) -> [CastDevice] {
        var out = primary
        for d in secondary where !out.contains(where: { $0.id == d.id }) {
            out.append(d)
        }
        return out
    }
}
