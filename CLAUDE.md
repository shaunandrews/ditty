# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

A minimal floating Apple Music controller for macOS built with SwiftUI. Displays current track info and basic playback controls.

## Development

```bash
swift build        # Build
swift run          # Run
open Package.swift # Open in Xcode
```

## Architecture

- **SwiftUI** app with Swift Package Manager
- **AppleScript bridge** for Music.app communication (no private APIs)
- **NSPanel** for floating/always-on-top window behavior
- Polls Music.app for track changes (no event API available)

## Key Files

- `Sources/MusicController/MusicBridge.swift` — All AppleScript interaction
- `Sources/MusicController/ContentView.swift` — The player UI
- `Sources/MusicController/WindowDelegate.swift` — Floating window management

## Scope

- **In scope**: Current track display, basic playback controls, floating window
- **Out of scope**: Queue/up-next, library browsing, playlist management, streaming
