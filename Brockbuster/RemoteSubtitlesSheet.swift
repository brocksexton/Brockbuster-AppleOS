import SwiftUI

struct RemoteSubtitlesSheet: View {
    let title: String
    let isLoading: Bool
    let errorMessage: String?
    let results: [JellyfinClient.RemoteSubtitleInfo]
    let onRefresh: () -> Void
    let onDownload: (JellyfinClient.RemoteSubtitleInfo) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if results.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No remote subtitles found.")
                                .font(.headline)
                            Text("If you recently enabled OpenSubtitles, ensure the plugin is configured on your Jellyfin server.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    Section("Results") {
                        ForEach(results) { sub in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sub.name ?? "Subtitle")
                                        .font(.headline)
                                        .lineLimit(2)
                                    HStack(spacing: 8) {
                                        if let language = sub.language, !language.isEmpty {
                                            Text(language)
                                        }
                                        if let format = sub.format, !format.isEmpty {
                                            Text(format.uppercased())
                                        }
                                        if let provider = sub.providerName, !provider.isEmpty {
                                            Text(provider)
                                        }
                                        if sub.isHearingImpaired == true {
                                            Text("SDH")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)

                                Button("Download") {
                                    onDownload(sub)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isLoading)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Subtitles")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onRefresh()
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }
}
