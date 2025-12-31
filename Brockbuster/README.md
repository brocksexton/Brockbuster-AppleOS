# Brockbuster Prototype

This folder contains a fresh starter codebase for the **Brockbuster** app—a
modern, multiplatform client for Jellyfin inspired by the classic Blockbuster
video store.  The aim is to provide a premium, nostalgic experience by
combining Apple’s latest design features (such as liquid glass effects and
rounded, tactile controls) with familiar colours and typography.

## Features

- **Server default**: Assumes your Jellyfin server lives at
  `https://vcr.brockbuster.lol`.  The `SessionStore` automatically fills
  this address and validates it via the `/health` endpoint on first use【515309828831105†L67-L69】.
- **Authentication**: Implements the `/Users/AuthenticateByName` login flow using
  the required JSON payload (`Username` and `Pw` fields) and attaches the
  `X-Emby-Authorization` header and custom `User‑Agent` to avoid Cloudflare
  bot checks【261741302448544†L73-L88】.
- **Retro loading screens**: Displays a VHS‑style loading overlay with animated
  scanlines and your Brockbuster logo while connecting to the server or
  signing in.
- **Professional UI**: Uses SwiftUI and a custom design system (`DesignSystem.swift`)
  to define colours, typography and a ticket‑style button.  Views are wrapped
  in translucent “liquid glass” cards that blur the background and stand out
  against the dark gradient.
- **Error handling**: Network errors and invalid inputs are surfaced to the
  user rather than letting the app hang.  Timeouts are set on all requests.
- **Logo support**: Place your logo images (`logo.png` and `logo-dark.png`) in
  the asset catalogue with names `logo` and `logo-dark`.  The views
  automatically pick the appropriate asset based on the current colour scheme.

## Files

- `JellyfinClient.swift` – Handles network requests (health check and
  authentication) with proper headers, JSON encoding and error handling.
- `JellyfinUser.swift` – Model representing the authenticated user.
- `SessionStore.swift` – Observable object storing server URL, current user and
  access token.  Provides methods to validate the server and log in.
- `DesignSystem.swift` – Defines colour palette, fonts, ticket button style and
  glass effect modifiers.  Includes a macOS `VisualEffectView` wrapper.
- `GlassCard.swift` – Reusable container view that wraps content in a
  translucent card with a coloured border and shadow.
- `RetroLoadingView.swift` – Animated loading overlay with moving stripes and
  optional status text.
- `ServerSetupView.swift` – A form for entering a custom server URL.  This
  screen isn’t currently used by the app by default but can be exposed if
  needed.
- `LoginView.swift` – Sign‑in screen with professional styling, error messages
  and login logic.
- `HomeView.swift` – Placeholder post‑login view showing a greeting and buttons
  to log out or change the server.
- `BrockbusterApp.swift` – The entry point that decides which view to display
  based on authentication state.

## Usage

1. **Add to Xcode project**: Drag the contents of the `brockbuster_new` folder
   into your Xcode project, ensuring that the files are added to all relevant
   targets (iOS, macOS, tvOS).
2. **Add assets**: Import your logo into the asset catalogue with the names
   `logo` and `logo-dark` to support light and dark modes.
3. **Build and run**: The app should launch directly to the login screen.  It
   will test connectivity to `https://vcr.brockbuster.lol` and then allow you
   to sign in.  If you need to connect to a different Jellyfin server, you can
   expose the `ServerSetupView` by presenting it from `LoginView` or
   adjusting the logic in `BrockbusterApp`.
4. **Enhance**: This starter lays the groundwork for building a fully featured
   Jellyfin client.  You can extend the `JellyfinClient` to fetch libraries,
   metadata and playback URLs, and populate the `HomeView` with dynamic
   content.
