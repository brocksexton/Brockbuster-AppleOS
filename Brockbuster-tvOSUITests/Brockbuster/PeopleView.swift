//
//  PeopleView.swift
//  Brockbuster
//
//  Created by Brock Sexton on 2025-12-31.
//

import SwiftUI

struct PeopleView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var vm = PeopleViewModel()
    @State private var searchText: String = ""

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    BrockbusterTheme.brockDark.opacity(0.6),
                    BrockbusterTheme.brockBlue.opacity(0.6)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    searchBar

                    if let error = vm.errorMessage {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Unable to load people", systemImage: "exclamationmark.triangle.fill")
                                    .font(BrockbusterTheme.Fonts.title)
                                    .foregroundColor(BrockbusterTheme.brockGold)

                                Text(error)
                                    .font(BrockbusterTheme.Fonts.body)
                                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.9))
                            }
                        }
                    }

                    if vm.isLoading {
                        GlassCard {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Loading directory…")
                                    .font(BrockbusterTheme.Fonts.body)
                                    .foregroundColor(BrockbusterTheme.brockLight)
                            }
                        }
                    }

                    resultsSection

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .refreshable {
                vm.query = searchText
                await vm.refresh(session: session)
            }
        }
        .navigationTitle("People")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
        .task {
            vm.query = ""
            await vm.refresh(session: session)
        }
    }

    private var header: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(BrockbusterTheme.brockGold)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Public Accounts")
                        .font(BrockbusterTheme.Fonts.title)
                        .foregroundColor(BrockbusterTheme.brockLight)

                    Text("Discover members who opted-in to public listing.")
                        .font(BrockbusterTheme.Fonts.body)
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))
                }

                Spacer()
            }
        }
    }

    private var searchBar: some View {
        GlassCard {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.8))

                TextField("Search by name…", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(BrockbusterTheme.brockLight)

                Button("Search") {
                    Task {
                        vm.query = searchText
                        await vm.refresh(session: session)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(BrockbusterTheme.brockGold.opacity(0.95))
            }
        }
    }

    private var resultsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("People")
                    .font(BrockbusterTheme.Fonts.title)
                    .foregroundColor(BrockbusterTheme.brockLight)

                if vm.results.isEmpty {
                    Text("No public accounts found.")
                        .font(BrockbusterTheme.Fonts.body)
                        .foregroundColor(BrockbusterTheme.brockLight.opacity(0.85))
                } else {
                    VStack(spacing: 10) {
                        // If Person is Identifiable you can keep ForEach(vm.results)
                        // Otherwise, this is safest:
                        ForEach(vm.results, id: \.id) { p in
                            personRow(p)
                        }
                    }
                }
            }
        }
    }

    private func personRow(_ p: BrockbusterAPI.PeoplePayload.Person) -> some View {
        // NOTE: These are camelCase (Swift), not snake_case.
        let name = p.displayName ?? "Unknown"
        let avatar = p.avatarUrl

        return HStack(spacing: 12) {
            AvatarView(
                urlString: avatar,
                fallbackText: initials(name)
            )
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(BrockbusterTheme.brockLight)

                Text((p.relationship ?? "none").capitalized)
                    .font(BrockbusterTheme.Fonts.body)
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.75))
            }

            Spacer()

            Text(actionLabel(p.relationship))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BrockbusterTheme.brockLight.opacity(0.12))
                .clipShape(Capsule())
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.9))
        }
        .padding(.vertical, 6)
    }

    private func actionLabel(_ rel: String?) -> String {
        switch rel?.lowercased() {
        case "friends": return "Friends"
        case "pending": return "Pending"
        default: return "Add"
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map(String.init)
        return chars.joined().uppercased()
    }
}
