import Foundation

enum BrockbusterFormat {
    static func year(_ value: Int?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    static func episodeLabel(season: Int?, episode: Int?) -> String {
        switch (season, episode) {
        case let (s?, e?):
            return "S\(s) • E\(e)"
        case let (s?, nil):
            return "S\(s)"
        case let (nil, e?):
            return "E\(e)"
        default:
            return ""
        }
    }
}
