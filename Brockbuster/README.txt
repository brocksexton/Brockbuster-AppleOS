Brockbuster – Build Fix Patch

This patch updates two files to restore multi-platform builds (iOS/iPadOS/tvOS/macOS):

1) PlayerView.swift
   - Replaces the iOS-only UIViewControllerRepresentable wrapper with a cross-platform implementation.
   - iOS/iPadOS/tvOS uses AVPlayerViewController.
   - macOS uses AVPlayerView.
   - Keeps the same PlayerView initializer (url/title/subtitle/posterURL/itemId) so existing call sites compile.

2) CollectionDetailView.swift
   - Fixes the SwiftUI type-check timeout by splitting the view into smaller computed subviews.
   - Updates the PlayerView sheet call to pass a concrete itemId (removes `nil` contextual-type issues).
   - Uses SessionStore.streamURL(for:) (already present in your SessionStore).

How to apply:
- Replace the existing files in your Xcode project with the ones in this zip.
  (Same filenames; if Xcode prompts, choose “Replace”.)

If you have local changes to these files, merge carefully.
