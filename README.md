# Brockbuster

<p align="center">
  <img src="assets/logo.png" width="420" />
</p>

<p align="center">
  <strong>A modern Apple-first Jellyfin client, wrapped in retro Blockbuster nostalgia.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-Apple-blue" />
  <img src="https://img.shields.io/badge/Jellyfin-Client-purple" />
  <img src="https://img.shields.io/badge/Platforms-iOS%20|%20iPadOS%20|%20macOS%20|%20tvOS-lightgrey" />
  <img src="https://img.shields.io/badge/Version-0.1.0-yellow" />
</p>

---

Brockbuster is a native SwiftUI client for [Jellyfin](https://jellyfin.org). Point it at your own
Jellyfin server, sign in, and go. It was originally built for a private community server; this
public release ships as a clean, generic client with the community-specific extras disabled
(but included in source — see [Companion service features](#-companion-service-features-optional)).

---

## 🚀 Getting Started

1. **Requirements**: Xcode with the iOS 26 / tvOS 26 / macOS 15 SDKs, and a Jellyfin server to connect to.
2. Clone the repo and open `Brockbuster.xcodeproj`.
3. In *Signing & Capabilities*, select your own development team and change the bundle identifiers.
4. Build and run the `Brockbuster` scheme for your platform of choice.
5. On first launch the app asks for your Jellyfin server address, then shows the login screen.

All build-time configuration lives in one file: [`Brockbuster/AppConfig.swift`](Brockbuster/AppConfig.swift).

| Setting | Default | What it does |
| --- | --- | --- |
| `defaultServerURL` | `nil` | Pre-configures a Jellyfin server for white-label builds. When `nil`, users are asked for a server on first launch. |
| `serviceBaseURL` | `nil` | Enables the optional companion-service features (Server Health, Friends, People). When `nil`, those features are hidden. |
| `bugReportWebhookURL` | `nil` | Enables in-app bug reports to a Discord webhook. When `nil`, the Report-a-Bug UI and shake gesture are disabled. |

---

## 🧭 Core Jellyfin Features

### Library Browsing
- Dedicated pages for **Movies**, **TV Series**, and **Collections**
- Full season & episode navigation
- Rich metadata views with artwork, descriptions, runtime, and year

### Playback & Streaming
- Automatic **Direct Play** when codecs are natively supported
- Intelligent **Transcoded stream fallback** when required
- Manual quality selection (Auto / 1080p / 720p / 480p)
- Skip Intro support (when available)
- Next Episode autoplay for TV series

### Watch State
- Continue Watching
- Watch History
- Resume playback across devices
- Favorites for Movies and TV Series

### Offline Viewing
- Download media directly to your device
- Choose between **Direct File Downloads** and **Server-side Transcoded Copies**
- Codec compatibility checks before download
- Download manager with progress tracking
- Fully offline playback with cached metadata & artwork

### Custom Player Experience
- Fully custom SwiftUI-based player
- Native Apple playback controls
- Background audio support
- Mini **Now Playing** bar while browsing
- Dynamic Island & system media controls (where supported)
- AirPlay, DLNA, and Chromecast/Roku casting groundwork

### Accounts
- Multiple remembered accounts with an account chooser
- Access tokens stored in the **Keychain**

---

## 🌐 Companion Service Features (optional)

The app also contains a set of community features that go beyond what Jellyfin itself offers:

- **Server Health dashboard** — real-time status, CPU/GPU/memory, and per-drive storage warnings
- **Friends** — friend lists and requests between users of the same server
- **People directory** — discover public profiles on your server

These are powered by a separate web service (not included in this repo) that the client talks to
using the user's Jellyfin token. **They are disabled by default** — the UI for them only appears
when you set `AppConfig.serviceBaseURL` to a service you run yourself.

The full API contract the client expects (endpoints, headers, response shapes) is documented in
[`docs/SERVICE_API.md`](docs/SERVICE_API.md), so you can implement a compatible backend for your
own community. The Swift models in
[`Brockbuster/BrockbusterAPI.swift`](Brockbuster/BrockbusterAPI.swift) are the authoritative
reference.

---

## 🐞 Bug Reporting

The app includes an in-app bug reporter (Settings → Report a Bug, or shake an iPhone) that posts
to a Discord webhook. It is **disabled by default**: set `AppConfig.bugReportWebhookURL` to enable
it. Remember that anything compiled into a public build is effectively public — for a distributed
app, prefer proxying reports through your own server instead of shipping a raw webhook URL.

---

## 🖥 Supported Platforms

- **iOS 26+**
- **iPadOS 26+**
- **macOS 15+**
- **tvOS 26+**

Built with SwiftUI for a consistent, native experience across all devices.

---

## ⚠️ Known Issues (0.1.0)

- **Offline downloads require polish**  
  Downloads may halt if the app is swiped away, and error handling can be inconsistent in some cases.

- **Next Episode metadata truncation**  
  When episodes auto-play, the player may fail to display the correct episode title, season number, or episode number.  
  This does not affect movies or the first episode played in a session.

- **UI clipping on Home screen**  
  Some text may render outside the visible area for TV Series or Episodes in Continue Watching or TV listings.

- **Additional bugs may exist**  
  As this is the first stable release, further issues may surface with broader usage.

---

## 📸 Screens

![iPhone Home](./assets/screenshots/v0.1.0-iphone-home.png)
![iPhone Series](./assets/screenshots/v0.1.0-iphone-series.png)
![iPad Login](./assets/screenshots/v0.1.0-ipad-login.png)
![iPad Player](./assets/screenshots/v0.1.0-ipad-player.png)
![tvOS Welcome Tour](./assets/screenshots/v0.1.0-tvOS-welcome.png)
![tvOS Shows Library](./assets/screenshots/v0.1.0-tvOS-shows.png)
![tvOS Server Health](./assets/screenshots/v0.1.0-tvOS-health.png)

---

## 📄 License & Trademarks

- Source code is released under the [MIT License](LICENSE).
- The Brockbuster name and logo are used for this project only; Brockbuster is **not affiliated
  with Blockbuster LLC**, and this project is **not affiliated with the Jellyfin project**.
- Designed for personal and community use with **self-hosted Jellyfin servers**. You are
  responsible for the content on your own server.

© Brock Sexton
