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

    static func bytes(_ value: Int?) -> String {
        guard let value else { return "—" }
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(value))
    }

    static func percent(used: Int?, total: Int?) -> String {
        guard let used, let total, total > 0 else { return "—" }
        let p = (Double(used) / Double(total)) * 100.0
        return String(format: "%.1f%%", p)
    }

    static func isoToDisplay(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        // server sends ISO 8601 via date('c')
        let formatter = ISO8601DateFormatter()
        if let d = formatter.date(from: iso) {
            let out = DateFormatter()
            out.dateStyle = .medium
            out.timeStyle = .medium
            return out.string(from: d)
        }
        return iso
    }
}
