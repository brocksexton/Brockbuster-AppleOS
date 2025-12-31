//
//  ServerHealthComponents.swift
//  Brockbuster
//
//  Created by Brock Sexton on 2025-12-31.
//

import SwiftUI

enum HealthSeverity: String {
    case healthy
    case warning
    case critical
    case unknown

    init(_ raw: String?) {
        switch raw?.lowercased() {
        case "healthy": self = .healthy
        case "warning": self = .warning
        case "critical": self = .critical
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }
}

struct SeverityPill: View {
    let severity: HealthSeverity

    var body: some View {
        Text(severity.label.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(backgroundColor.opacity(0.22))
            )
            .overlay(
                Capsule().strokeBorder(backgroundColor.opacity(0.35), lineWidth: 1)
            )
            .foregroundColor(foregroundColor)
    }

    private var backgroundColor: Color {
        switch severity {
        case .healthy: return BrockbusterTheme.brockGold
        case .warning: return BrockbusterTheme.brockGold
        case .critical: return Color.red
        case .unknown: return BrockbusterTheme.brockLight
        }
    }

    private var foregroundColor: Color {
        switch severity {
        case .critical: return Color.red
        default: return BrockbusterTheme.brockLight
        }
    }
}

struct RolePill: View {
    let role: String?

    var body: some View {
        let text = (role ?? "").lowercased()
        Text(text.isEmpty ? "—" : text.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(BrockbusterTheme.brockLight.opacity(0.10)))
            .overlay(Capsule().strokeBorder(BrockbusterTheme.brockLight.opacity(0.18), lineWidth: 1))
            .foregroundColor(BrockbusterTheme.brockLight.opacity(0.9))
    }
}

struct UsageBar: View {
    let fraction: Double? // 0...1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fill = max(0, min(1, fraction ?? 0)) * w

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(BrockbusterTheme.brockLight.opacity(0.10))

                RoundedRectangle(cornerRadius: 10)
                    .fill(BrockbusterTheme.brockGold.opacity(0.85))
                    .frame(width: fill)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Usage")
    }
}
