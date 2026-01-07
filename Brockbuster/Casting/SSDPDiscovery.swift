import Foundation
import Network

/// Minimal SSDP M-SEARCH discovery client.
///
/// This is intentionally lightweight: it sends a multicast M-SEARCH query
/// and gathers unicast responses for a short window. This is enough to
/// discover most DLNA/UPnP MediaRenderer devices (smart TVs, boxes, etc.).
final class SSDPDiscovery {
    struct Response: Equatable {
        let usn: String?
        let st: String?
        let location: URL?
        let server: String?
        let raw: String
    }

    private var connection: NWConnection?
    private var receiveTask: Task<Void, Never>?

    func search(st: String, mx: Int = 1, timeout: TimeInterval = 2.0) async -> [Response] {
        let host = NWEndpoint.Host("239.255.255.250")
        let port = NWEndpoint.Port(integerLiteral: 1900)
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true

        let conn = NWConnection(host: host, port: port, using: parameters)
        self.connection = conn

        let queue = DispatchQueue(label: "ssdp.discovery")
        conn.start(queue: queue)

        // Wait until ready (or fail quickly).
        var isReady = false
        let readySemaphore = DispatchSemaphore(value: 0)
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                isReady = true
                readySemaphore.signal()
            case .failed, .cancelled:
                readySemaphore.signal()
            default:
                break
            }
        }
        _ = readySemaphore.wait(timeout: .now() + 1.5)
        guard isReady else {
            conn.cancel()
            self.connection = nil
            return []
        }

        let request = Self.makeMSearch(st: st, mx: mx)
        let requestData = request.data(using: .utf8) ?? Data()
        conn.send(content: requestData, completion: .contentProcessed { _ in })

        var results: [Response] = []
        let lock = NSLock()

        // Receive loop for a fixed time window.
        receiveTask = Task {
            while !Task.isCancelled {
                let r = await withCheckedContinuation { (cont: CheckedContinuation<Response?, Never>) in
                    conn.receiveMessage { data, _, _, _ in
                        guard let data, !data.isEmpty else {
                            cont.resume(returning: nil)
                            return
                        }
                        let raw = String(decoding: data, as: UTF8.self)
                        cont.resume(returning: Self.parseResponse(raw))
                    }
                }

                if let r {
                    lock.lock()
                    // De-dupe by Location+USN.
                    let key = "\(r.location?.absoluteString ?? "")|\(r.usn ?? "")"
                    let exists = results.contains(where: { (existing) in
                        "\(existing.location?.absoluteString ?? "")|\(existing.usn ?? "")" == key
                    })
                    if !exists {
                        results.append(r)
                    }
                    lock.unlock()
                }
            }
        }

        // Wait discovery window
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        receiveTask?.cancel()
        receiveTask = nil
        conn.cancel()
        self.connection = nil

        return results
    }

    private static func makeMSearch(st: String, mx: Int) -> String {
        // SSDP uses CRLF line endings.
        return [
            "M-SEARCH * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            "MAN: \"ssdp:discover\"",
            "MX: \(mx)",
            "ST: \(st)",
            "",
            ""
        ].joined(separator: "\r\n")
    }

    private static func parseResponse(_ raw: String) -> Response {
        var headers: [String: String] = [:]
        let lines = raw.split(whereSeparator: \.isNewline).map { String($0) }
        for line in lines {
            if let idx = line.firstIndex(of: ":") {
                let key = String(line[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                headers[key] = value
            }
        }
        let location = headers["location"].flatMap { URL(string: $0) }
        return Response(
            usn: headers["usn"],
            st: headers["st"],
            location: location,
            server: headers["server"],
            raw: raw
        )
    }
}
