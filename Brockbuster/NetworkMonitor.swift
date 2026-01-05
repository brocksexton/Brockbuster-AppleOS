import Foundation
import Network

/// Lightweight reachability / path quality monitor.
///
/// We use this to make a conservative Direct Play decision:
/// - If the path is expensive (cellular) or constrained, we may still choose HLS.
/// - Otherwise, when the file is Apple-compatible we prefer Direct Play to reduce server load.
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isExpensive: Bool = false
    @Published private(set) var isConstrained: Bool = false
    @Published private(set) var isSatisfied: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isSatisfied = (path.status == .satisfied)
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
            }
        }
        monitor.start(queue: queue)
    }
}
