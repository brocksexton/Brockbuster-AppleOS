# Brockbuster — Source Overview

Quick map of the main app target for new contributors. See the repo-level
[README](../README.md) for build instructions and configuration.

## Core

- `BrockbusterApp.swift` — entry point; picks server setup / login / main UI based on session state, and hosts the shake-to-report gesture.
- `AppConfig.swift` — all build-time configuration (default server, optional companion service, bug-report webhook). Everything is off by default.
- `SessionStore.swift` — observable session state: server URL, current user, token, libraries, connectivity (including sticky offline mode).
- `JellyfinClient.swift` — Jellyfin HTTP client (health check, `/Users/AuthenticateByName` login with `X-Emby-Authorization`, library/metadata/playback requests).
- `JellyfinUser.swift` — authenticated-user model.
- `AccountManager.swift` + `KeychainHelper.swift` — remembered accounts; access tokens live in the Keychain.

## UI

- `MainTabView.swift` — post-login tab bar (Home / My / [Health] / More).
- `HomeView.swift`, `LibraryDetailView.swift`, `ItemDetailView.swift`, `SeriesDetailView.swift`, `SeasonDetailView.swift`, `CollectionDetailView.swift` — browsing.
- `MyBrockbusterView.swift` — continue watching, history, favourites, downloads.
- `MoreView.swift` — secondary screens (membership, server & login, settings, community, bug reporting).
- `LoginView.swift`, `ServerSetupView.swift`, `AccountChooserView.swift`, `AutoSignInView.swift`, `OnboardingHostView.swift`, `WelcomeTourView.swift` — auth + first-run flows.
- `DesignSystem.swift`, `GlassCard.swift`, `RetroLoadingView.swift` — theme, glass cards, VHS-style loading overlay.

## Playback

- `Player/` + `CustomPlayer/` + `PlayerView.swift` — custom SwiftUI player with AVKit fallbacks per platform.
- `NowPlayingManager.swift`, `NowPlayingBar.swift`, `NowPlayingFullscreenView.swift` — mini-player and fullscreen presentation.
- `DownloadManager.swift`, `DownloadsView.swift`, `OfflineServerView.swift` — offline downloads and offline-first UI.
- `Casting/` — AirPlay, DLNA (SSDP discovery + SOAP control), and Chromecast/Roku groundwork.
- `LiveActivities/` — Live Activity / widget support for Now Playing.

## Companion service (optional, disabled by default)

- `BrockbusterAPI.swift` — client for the separate community service; contract in [`docs/SERVICE_API.md`](../docs/SERVICE_API.md).
- `ServerHealthViewModel.swift`, `ServerHealthComponents.swift` — Server Health tab.
- `FriendsView.swift`, `FriendsViewModel.swift`, `FriendRow.swift` — friends list.
- `PeopleView.swift`, `PeopleViewModel.swift`, `Person.swift` — public-profile directory.
- `MembershipCardView.swift` — membership card (local data only; works without the service).

These stay in the codebase as a starting point for building your own community backend; the UI
for them appears only when `AppConfig.serviceBaseURL` is set.
