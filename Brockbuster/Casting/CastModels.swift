import Foundation

enum CastProviderKind: String, CaseIterable, Identifiable, Codable {
    case airPlay
    case dlna
    case googleCast
    case roku
    case brockbusterReceiver

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .airPlay: return "AirPlay"
        case .dlna: return "Smart TVs (DLNA)"
        case .googleCast: return "Chromecast"
        case .roku: return "Roku"
        case .brockbusterReceiver: return "Brockbuster"
        }
    }

    var systemImageName: String {
        switch self {
        case .airPlay: return "airplayvideo"
        case .dlna: return "display.2"
        case .googleCast: return "tv"
        case .roku: return "tv.and.hifispeaker.fill"
        case .brockbusterReceiver: return "sparkles.tv"
        }
    }
}

struct CastDevice: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let provider: CastProviderKind
    let detail: String?
}

struct CastConnectionState: Equatable {
    var isConnected: Bool { connectedDevice != nil }
    var connectedDevice: CastDevice? = nil
}
