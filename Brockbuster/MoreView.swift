import SwiftUI
import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// A consolidated list of secondary screens that don't need their own bottom-tab.
/// This menu is intended to be extensible as Brockbuster grows (accounts, friends,
/// stats/health, settings, etc.).
@MainActor
struct MoreView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showingLogoutConfirm = false

    // Session-derived values used in multiple subviews.
    private var currentUsername: String {
        session.currentUser?.name ?? "Not signed in"
    }

    private var currentServer: String {
        session.serverURL.host ?? session.serverURL.absoluteString
    }

    var body: some View {
        #if os(tvOS)
        tvLayout
        #else
        List {
            Section("Account") {
                NavigationLink(destination: MembershipCardView()) {
                    Label("Membership", systemImage: "wallet.pass")
                }

                NavigationLink(destination: ServerSetupView()) {
                    Label("Server & Login", systemImage: "server.rack")
                }

                NavigationLink(destination: SettingsTab()) {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }

            Section("Community") {
                NavigationLink(destination: FriendsView()) {
                    Label("Friends", systemImage: "person.2.fill")
                }

                NavigationLink(destination: SocialTab()) {
                    Label("Social Feed", systemImage: "quote.bubble.fill")
                }

                NavigationLink(destination: PeopleView()) {
                    Label("People", systemImage: "person.crop.square")
                }
            }

            Section("System") {
                NavigationLink(destination: ServerHealthTab()) {
                    Label("Server Health", systemImage: "waveform.path.ecg")
                }
            }

            Section {
                Button(role: .destructive) {
                    showingLogoutConfirm = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("More")
        #if !os(macOS)
        .bbNavigationTitleLarge()
        #endif
        .alert("Sign out of Brockbuster?", isPresented: $showingLogoutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                session.logout()
            }
        } message: {
            Text("You will need to sign in again to access your libraries.")
        }
        #endif
    }

    #if os(tvOS)
    private var tvLayout: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.65), BrockbusterTheme.brockBlue.opacity(0.55)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("More")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(BrockbusterTheme.brockLight)
                        .padding(.top, 6)

                    MoreSectionCard(title: "Account") {
                        MoreRowLink(title: "Membership", systemImage: "wallet.pass") {
                            MembershipCardView()
                        }
                        MoreRowLink(title: "Server & Login", systemImage: "server.rack") {
                            ServerSetupView()
                        }
                        MoreRowLink(title: "Settings", systemImage: "gearshape.fill") {
                            SettingsTab()
                        }
                    }

                    MoreSectionCard(title: "Community") {
                        MoreRowLink(title: "Friends", systemImage: "person.2.fill") {
                            FriendsView()
                        }
                        MoreRowLink(title: "Social Feed", systemImage: "quote.bubble.fill") {
                            SocialTab()
                        }
                        MoreRowLink(title: "People", systemImage: "person.crop.square") {
                            PeopleView()
                        }
                    }

                    MoreSectionCard(title: "System") {
                        MoreRowLink(title: "Server Health", systemImage: "waveform.path.ecg") {
                            ServerHealthTab()
                        }
                    }

                    MoreSectionCard(title: "") {
                        Button(role: .destructive) {
                            showingLogoutConfirm = true
                        } label: {
                            MoreRow(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right", isDestructive: true)
                        }
                        .buttonStyle(.plain)
                        .bbTVFocusCard(cornerRadius: 18)
                    }

                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 46)
                .padding(.bottom, 40)
                .frame(maxWidth: 1400, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("More")
        .bbNavigationTitleInline()
        .alert("Sign out of Brockbuster?", isPresented: $showingLogoutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                session.logout()
            }
        } message: {
            Text("You will need to sign in again to access your libraries.")
        }
    }
    #endif
}

#if os(tvOS)
private struct MoreSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.88))
                    .padding(.horizontal, 6)
            }

            VStack(spacing: 10) {
                content()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct MoreRowLink<Destination: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            MoreRow(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .bbTVFocusCard(cornerRadius: 18)
    }
}

private struct MoreRow: View {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(BrockbusterTheme.brockGold.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(BrockbusterTheme.brockGold)
            }

            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(isDestructive ? .red : BrockbusterTheme.brockLight)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
#endif

// MARK: - Bug Reporting

/// Simple in-app bug reporter that posts a structured message to a Discord webhook.
///
/// Notes:
/// - Intentionally avoids collecting any sensitive information.
/// - Keeps payload small to fit Discord embed limits.
@MainActor
struct BugReportView: View {
    enum EntryPoint: String {
        case settings
        case shake
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    let entryPoint: EntryPoint

    @State private var subject: String = ""
    @State private var details: String = ""
    @State private var includeDiagnostics: Bool = true

    @State private var isSending: Bool = false
    @State private var sentSuccessfully: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Send a quick report to Brock via Discord. Please avoid sharing passwords, tokens, or private information.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("What happened?")) {
                #if !os(tvOS)
                TextEditor(text: $details)
                    .frame(minHeight: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.secondary.opacity(0.25), lineWidth: 1)
                    )
                #else
                Text("Enter details on iPhone or iPad to include more information.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(minHeight: 140, alignment: .topLeading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.secondary.opacity(0.25), lineWidth: 1)
                    )
                #endif
            }

            Section {
                Toggle("Include device + app info", isOn: $includeDiagnostics)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Report a Bug")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Text("Send")
                    }
                }
                .disabled(isSending || (subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .alert("Thanks!", isPresented: $sentSuccessfully) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your report was sent.")
        }
        .onAppear {
            if subject.isEmpty && entryPoint == .shake {
                subject = "Quick bug report"
            }
        }
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let diagnostics = includeDiagnostics
            ? await BugReportDiagnostics.build(session: session, entryPoint: entryPoint)
            : nil

        do {
            try await BugReportService.shared.send(
                subject: subject,
                details: details,
                diagnostics: diagnostics
            )
            sentSuccessfully = true
        } catch {
            errorMessage = "Failed to send report: \(error.localizedDescription)"
        }
    }
}

private struct BugReportDiagnostics {
    let appName: String
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let device: String
    let locale: String
    let timeZone: String
    let server: String
    let user: String
    let entryPoint: String
    let timestampISO8601: String

	static func build(session: SessionStore, entryPoint: BugReportView.EntryPoint) async -> BugReportDiagnostics {
		return await MainActor.run {
        let bundle = Bundle.main
        let appName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Brockbuster"
        let appVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let device = BugReportPlatform.deviceDescription

        let locale = Locale.current.identifier
        let timeZone = TimeZone.current.identifier

        let server = session.serverURL.host ?? session.serverURL.absoluteString
        let user = session.currentUser?.name ?? "Not signed in"

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

		return .init(
            appName: appName,
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            device: device,
            locale: locale,
            timeZone: timeZone,
            server: server,
            user: user,
            entryPoint: entryPoint.rawValue,
            timestampISO8601: timestamp
		)
		}
    }

    var asMarkdown: String {
        var lines: [String] = []
        lines.append("App: \(appName) \(appVersion) (\(buildNumber))")
        lines.append("OS: \(osVersion)")
        lines.append("Device: \(device)")
        lines.append("Locale: \(locale)")
        lines.append("Time Zone: \(timeZone)")
        lines.append("Server: \(server)")
        lines.append("User: \(user)")
        lines.append("Entry: \(entryPoint)")
        lines.append("Time: \(timestampISO8601)")
        return lines.joined(separator: "\n")
    }
}

private enum BugReportPlatform {
    static var deviceDescription: String {
        #if canImport(UIKit)
        #if os(tvOS)
        return "Apple TV"
        #else
        let name = UIDevice.current.name
        let model = UIDevice.current.model
        let system = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        return "\(model) — \(name) — \(system)"
        #endif
        #elseif canImport(AppKit)
        return "Mac"
        #else
        return "Unknown"
        #endif
    }
}

private final class BugReportService {
    static let shared = BugReportService()
    private init() {}

    /// Discord webhook for bug reports.
    ///
    /// If you ever need to rotate this, change the URL string and ship an update.
    private let webhookURLString = "https://discord.com/api/webhooks/1456861309084893408/akz7vo4PN-LDW3CLDwYXwcNsN87Iunx12XtVe3IgOcktgns-PjPlIqaIdL-kwulgjvta"

    struct DiscordPayload: Codable {
        let username: String?
        let content: String?
        let embeds: [Embed]?

        struct Embed: Codable {
            let title: String?
            let description: String?
            let timestamp: String?
        }
    }

    func send(subject: String, details: String, diagnostics: BugReportDiagnostics?) async throws {
        guard let url = URL(string: webhookURLString) else {
            throw URLError(.badURL)
        }

        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        var descriptionParts: [String] = []

        if !trimmedDetails.isEmpty {
            descriptionParts.append(trimmedDetails)
        }
        if let diagnostics {
            descriptionParts.append("\n**Diagnostics**\n```\n\(diagnostics.asMarkdown)\n```")
        }

        let fullDescription = descriptionParts.joined(separator: "\n\n")
        let safeDescription = BugReportService.truncate(fullDescription, max: 3500)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

        let payload = DiscordPayload(
            username: "Brockbuster Bug Reporter",
            content: nil,
            embeds: [
                .init(
                    title: trimmedSubject.isEmpty ? "Bug Report" : BugReportService.truncate(trimmedSubject, max: 200),
                    description: safeDescription.isEmpty ? "(no details provided)" : safeDescription,
                    timestamp: timestamp
                )
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw NSError(domain: "BugReportService", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Discord returned HTTP \(http.statusCode)."
            ])
        }
    }

    private static func truncate(_ value: String, max: Int) -> String {
        guard value.count > max else { return value }
        let idx = value.index(value.startIndex, offsetBy: max)
        return String(value[..<idx]) + "…"
    }
}


/// Placeholder settings view to demonstrate adding additional pages. You can
/// customize this with real settings for the app such as theme, cache management,
/// and account linking.
@MainActor
struct SettingsTab: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var accountManager: AccountManager

    // Session-derived values (kept local to this view to avoid cross-type scope issues).
    private var currentUsername: String {
        session.currentUser?.name ?? "Not signed in"
    }

    private var currentServer: String {
        session.serverURL.host ?? session.serverURL.absoluteString
    }

    @AppStorage("settings.defaultRememberAccount") private var defaultRememberAccount: Bool = true
    @AppStorage("settings.showAccountChooserOnLaunch") private var showAccountChooserOnLaunch: Bool = true
    @AppStorage("onboarding.didComplete") private var didCompleteOnboarding: Bool = false
    @AppStorage("onboarding.preferSkip") private var preferSkipOnboarding: Bool = false
    @AppStorage("onboarding.forceShowNextLaunch") private var forceShowOnboardingNextLaunch: Bool = false
    @AppStorage("onboarding.presentNow") private var presentOnboardingNow: Bool = false

    @State private var clearCacheOnLogout: Bool = false
    @State private var preferDarkMode: Bool = true

    @State private var presentBugReport: Bool = false

    var body: some View {
        #if os(tvOS)
        tvSettingsLayout
        #else
        Form {
            Section(header: Text("Account")) {
                HStack {
                    Text("Username")
                    Spacer()
                    Text(currentUsername)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Server")
                    Spacer()
                    Text(currentServer)
                        .foregroundColor(.secondary)
                }
                if let join = session.joinDate {
                    HStack {
                        Text("Member Since")
                        Spacer()
                        Text(join.formatted(date: .abbreviated, time: .omitted))
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink {
                    ManageAccountsView()
                } label: {
                    Label("Remembered Accounts", systemImage: "person.2.circle")
                }
            }

            Section(header: Text("App Settings")) {
                Toggle("Enable Dark Mode", isOn: $preferDarkMode)
                Toggle("Clear Cache on Logout", isOn: $clearCacheOnLogout)
                Toggle("Default to remembering accounts", isOn: $defaultRememberAccount)
                Toggle("Show account chooser on launch", isOn: $showAccountChooserOnLaunch)

            }

            Section(header: Text("Welcome Tour")) {
                Button {
                    // Present immediately (works even before login).
                    preferSkipOnboarding = false
                    didCompleteOnboarding = false
                    presentOnboardingNow = true
                } label: {
                    Label("Show welcome tour now", systemImage: "sparkles")
                }

                Toggle(isOn: Binding(
                    get: { forceShowOnboardingNextLaunch },
                    set: { newValue in
                        // If enabling, ensure it isn't considered skipped.
                        if newValue {
                            preferSkipOnboarding = false
                            didCompleteOnboarding = false
                        }
                        forceShowOnboardingNextLaunch = newValue
                    }
                )) {
                    Text("Show tour on next launch")
                }
            }

            Section(header: Text("About")) {
                Text("Brockbuster is a Jellyfin-powered client designed for a premium, cinema-first experience.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Support")) {
                Button {
                    presentBugReport = true
                } label: {
                    Label("Report a Bug", systemImage: "ladybug")
                }
            }
        }
        .navigationTitle("Settings")
        #if !os(macOS)
        .bbNavigationTitleInline()
        #endif
        .sheet(isPresented: $presentBugReport) {
            NavigationStack {
                BugReportView(entryPoint: .settings)
                    .environmentObject(session)
            }
        }
        #endif
    }

    #if os(tvOS)
    private var tvSettingsLayout: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [BrockbusterTheme.brockDark.opacity(0.65), BrockbusterTheme.brockBlue.opacity(0.55)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(BrockbusterTheme.brockLight)
                        .padding(.top, 6)

                    MoreSectionCard(title: "Account") {
                        SettingsInfoRow(title: "Username", value: currentUsername)
                        SettingsInfoRow(title: "Server", value: currentServer)
                        if let join = session.joinDate {
                            SettingsInfoRow(title: "Member Since", value: join.formatted(date: .abbreviated, time: .omitted))
                        }

                        NavigationLink {
                            ManageAccountsView()
                        } label: {
                            MoreRow(title: "Remembered Accounts", systemImage: "person.2.circle")
                        }
                        .buttonStyle(.plain)
                        .bbTVFocusCard(cornerRadius: 18)
                    }

                    MoreSectionCard(title: "App Settings") {
                        SettingsToggleRow(title: "Enable Dark Mode", isOn: $preferDarkMode)
                        SettingsToggleRow(title: "Clear Cache on Logout", isOn: $clearCacheOnLogout)
                        SettingsToggleRow(title: "Default to remembering accounts", isOn: $defaultRememberAccount)
                        SettingsToggleRow(title: "Show account chooser on launch", isOn: $showAccountChooserOnLaunch)
                    }

                    MoreSectionCard(title: "Welcome Tour") {
                        Button {
                            // Present immediately.
                            preferSkipOnboarding = false
                            didCompleteOnboarding = false
                            presentOnboardingNow = true
                        } label: {
                            MoreRow(title: "Show welcome tour now", systemImage: "sparkles")
                        }
                        .buttonStyle(.plain)
                        .bbTVFocusCard(cornerRadius: 18)

                        SettingsToggleRow(title: "Show tour on next launch", isOn: Binding(
                            get: { forceShowOnboardingNextLaunch },
                            set: { newValue in
                                if newValue {
                                    preferSkipOnboarding = false
                                    didCompleteOnboarding = false
                                }
                                forceShowOnboardingNextLaunch = newValue
                            }
                        ))
                    }

                    MoreSectionCard(title: "About") {
                        Text("Brockbuster is a Jellyfin-powered client designed for a premium, cinema-first experience.")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(BrockbusterTheme.brockLight.opacity(0.82))
                            .padding(.horizontal, 6)
                    }

                    MoreSectionCard(title: "Support") {
                        Button {
                            presentBugReport = true
                        } label: {
                            MoreRow(title: "Report a Bug", systemImage: "ladybug")
                        }
                        .buttonStyle(.plain)
                        .bbTVFocusCard(cornerRadius: 18)
                    }

                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 46)
                .padding(.bottom, 40)
                .frame(maxWidth: 1400, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Settings")
        .bbNavigationTitleInline()
        .sheet(isPresented: $presentBugReport) {
            NavigationStack {
                BugReportView(entryPoint: .settings)
                    .environmentObject(session)
            }
        }
    }
    #endif
}

#if os(tvOS)
private struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight.opacity(0.70))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(BrockbusterTheme.brockLight)
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        // Give the row focus styling rather than the toggle's giant default.
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .bbTVFocusCard(cornerRadius: 18)
    }
}
#endif

#if DEBUG
struct MoreView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MoreView()
                .environmentObject(SessionStore())
                .environmentObject(AccountManager())
        }
    }
}
#endif
