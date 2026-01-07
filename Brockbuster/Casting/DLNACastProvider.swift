import Foundation

/// DLNA/UPnP "MediaRenderer" casting provider.
///
/// This supports a large number of smart TVs and set-top boxes that expose
/// the AVTransport service. It works by:
/// 1) Discovering devices via SSDP M-SEARCH for `urn:schemas-upnp-org:device:MediaRenderer:1`
/// 2) Fetching the device description XML to resolve the AVTransport `controlURL`
/// 3) Calling `SetAVTransportURI` + `Play` over SOAP
final class DLNACastProvider: BaseCastProvider {
    private let ssdp = SSDPDiscovery()

    private var discoveryTask: Task<Void, Never>?
    private var currentControlURL: URL?

    override init(kind: CastProviderKind = .dlna) {
        super.init(kind: kind)
    }

    override func startDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = Task {
            // Re-run discovery periodically while the sheet is open.
            while !Task.isCancelled {
                let responses = await ssdp.search(st: "urn:schemas-upnp-org:device:MediaRenderer:1", mx: 1, timeout: 2.0)
                let devices = await resolveDevices(from: responses)
                await MainActor.run {
                    self.setDevices(devices)
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    override func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    override func connect(to device: CastDevice) {
        super.connect(to: device)
        // `device.id` stores the AVTransport control URL.
        currentControlURL = URL(string: device.id)
    }

    override func disconnect() {
        super.disconnect()
        currentControlURL = nil
    }

    override func loadMedia(_ payload: CastMediaPayload) {
        guard let controlURL = currentControlURL else { return }
        Task {
            do {
                try await setAVTransportURI(controlURL: controlURL, uri: payload.url.absoluteString)
                try await play(controlURL: controlURL)
            } catch {
                // Best-effort: keep the UI responsive even if a device rejects the command.
                // (Some devices require additional metadata or only accept certain formats.)
                print("DLNA cast failed: \(error)")
            }
        }
    }

    // MARK: - Device resolution

    private func resolveDevices(from responses: [SSDPDiscovery.Response]) async -> [CastDevice] {
        var out: [CastDevice] = []
        for r in responses {
            guard let location = r.location else { continue }
            guard let host = location.host else { continue }

            do {
                let (data, _) = try await URLSession.shared.data(from: location)
                let parser = UPnPDeviceDescriptionParser(baseURL: location)
                guard let desc = parser.parse(data: data) else { continue }

                // Prefer AVTransport v1.
                let av = desc.services.first(where: { $0.serviceType.contains("AVTransport") })
                guard let controlURL = av?.controlURL else { continue }

                // Use the control URL as the device id so we can invoke it later.
                let device = CastDevice(
                    id: controlURL.absoluteString,
                    name: desc.friendlyName,
                    provider: .dlna,
                    detail: host
                )
                out.append(device)
            } catch {
                continue
            }
        }
        // Stable sort by name.
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - SOAP control

    private func setAVTransportURI(controlURL: URL, uri: String) async throws {
        let body = """
        <?xml version=\"1.0\" encoding=\"utf-8\"?>
        <s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">
          <s:Body>
            <u:SetAVTransportURI xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">
              <InstanceID>0</InstanceID>
              <CurrentURI>\(escapeXML(uri))</CurrentURI>
              <CurrentURIMetaData></CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """
        try await soap(controlURL: controlURL, action: "SetAVTransportURI", body: body)
    }

    private func play(controlURL: URL) async throws {
        let body = """
        <?xml version=\"1.0\" encoding=\"utf-8\"?>
        <s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">
          <s:Body>
            <u:Play xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">
              <InstanceID>0</InstanceID>
              <Speed>1</Speed>
            </u:Play>
          </s:Body>
        </s:Envelope>
        """
        try await soap(controlURL: controlURL, action: "Play", body: body)
    }

    private func soap(controlURL: URL, action: String, body: String) async throws {
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#\(action)\"", forHTTPHeaderField: "SOAPAction")
        request.timeoutInterval = 6
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "DLNA", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
    }

    private func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
