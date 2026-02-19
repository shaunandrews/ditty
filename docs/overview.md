# Music Controller — Overview

## What Is This?

A minimal macOS app that shows what's currently playing in Apple Music with basic controls. Born out of frustration with Apple Music's cluttered UI — sometimes you just want to see the song, the artist, and the album art without wading through a full media player.

Built with SwiftUI and communicates with Music.app via AppleScript. Supports floating above other windows so it's always visible while you work.

## Architecture

- **Swift Package Manager** project (no Xcode project file needed)
- **SwiftUI** for the UI
- **AppleScript** via `NSAppleScript` for Music.app communication
- **NSPanel** subclass for always-on-top floating behavior
- Polls every ~1 second for track changes (Apple Music has no change notification API)

## Key People

- **Shaun Andrews** — Creator, design direction

## What's Next

- Build the initial working prototype
- Nail the UI — clean, readable, beautiful
- Test floating window behavior across Spaces/fullscreen apps
