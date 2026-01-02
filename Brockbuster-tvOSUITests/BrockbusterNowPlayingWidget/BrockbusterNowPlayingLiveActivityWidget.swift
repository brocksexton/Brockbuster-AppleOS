import WidgetKit
import SwiftUI
import ActivityKit

/// Live Activity / Dynamic Island UI for Brockbuster Now Playing.
///
/// To enable:
/// 1) In Xcode: File > New > Target... > Widget Extension, check "Include Live Activity".
/// 2) Add this file to the widget extension target membership.
/// 3) Ensure BrockbusterNowPlayingAttributes.swift is included in both the app target and the widget extension.
struct BrockbusterNowPlayingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BrockbusterNowPlayingAttributes.self) { context in
            // Lock Screen / StandBy UI
            HStack(spacing: 12) {
                if let s = context.attributes.posterURLString,
                   let url = URL(string: s) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color.secondary.opacity(0.2)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.seriesTitle ?? context.state.title)
                        .font(.headline)
                        .lineLimit(1)

                    // Prefer structured episode metadata when present.
                    let s = context.state.seasonNumber
                    let e = context.state.episodeNumber
                    let epTitle = context.state.episodeTitle
                    let hasStructured = (s != nil) || (e != nil) || ((epTitle?.isEmpty == false))

                    if hasStructured {
                        let se = [
                            s.map { "S\($0)" },
                            e.map { "E\($0)" }
                        ].compactMap { $0 }.joined(separator: " • ")

                        let line = se + (epTitle.map { se.isEmpty ? $0 : " — \($0)" } ?? "")

                        if !line.isEmpty {
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else if let sub = context.state.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if context.state.durationSeconds > 0 {
                        ProgressView(value: context.state.positionSeconds, total: context.state.durationSeconds)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let s = context.attributes.posterURLString,
                       let url = URL(string: s) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Color.secondary.opacity(0.2)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.seriesTitle ?? context.state.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        let s = context.state.seasonNumber
                        let e = context.state.episodeNumber
                        let epTitle = context.state.episodeTitle
                        let hasStructured = (s != nil) || (e != nil) || ((epTitle?.isEmpty == false))

                        if hasStructured {
                            let se = [
                                s.map { "S\($0)" },
                                e.map { "E\($0)" }
                            ].compactMap { $0 }.joined(separator: " • ")

                            let line = se + (epTitle.map { se.isEmpty ? $0 : " — \($0)" } ?? "")

                            if !line.isEmpty {
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else if let sub = context.state.subtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.durationSeconds > 0 {
                        ProgressView(value: context.state.positionSeconds, total: context.state.durationSeconds)
                    }
                }

            } compactLeading: {
                Image(systemName: "film")
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
            } minimal: {
                Image(systemName: "film")
            }
        }
    }
}
