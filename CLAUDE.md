# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A minimal floating Apple Music controller for macOS built with SwiftUI. Displays current track info and basic playback controls.

## Development

```bash
swift build        # Build
swift run          # Run
open Package.swift # Open in Xcode
```

No tests currently. macOS 14+ (Sonoma) required. The app will prompt for Automation permission on first launch to control Music.app, and System Audio Recording permission for the visualizer.

## Architecture

- **SwiftUI** app with Swift Package Manager (single executable target)
- **AppleScript bridge** for Music.app communication — no private APIs, no MusicKit
- **NSPanel-style floating window** via `AppDelegate` in `App.swift` (sets `window.level = .floating`)
- **Polling model**: `MusicBridge` polls Music.app every 1 second via `Timer`. There is no event/notification API available from Music.app. Control actions (play/pause, next, previous) trigger an immediate re-poll after 300ms.

## Key Files

- `Sources/MusicController/MusicBridge.swift` — All AppleScript interaction. Uses `||`-delimited string responses parsed into `TrackInfo`. Artwork fetched separately as raw data.
- `Sources/MusicController/ContentView.swift` — The player UI. Owns the `MusicBridge` instance as `@StateObject`. Handles float/pin toggle.
- `Sources/MusicController/AudioAnalyzer.swift` — Core Audio Process Tap for real-time audio visualization. Taps Music.app's audio output directly (no microphone). Uses `CATapDescription` + aggregate device + IO proc callback, feeding PCM buffers through vDSP FFT.
- `Sources/MusicController/App.swift` — App entry point and `AppDelegate` for floating window setup.

## Scope

- **In scope**: Current track display, basic playback controls, floating window
- **Out of scope**: Queue/up-next, library browsing, playlist management, streaming
