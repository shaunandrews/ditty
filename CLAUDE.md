# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ditty — a minimal floating Apple Music controller for macOS built with SwiftUI. Displays current track info, basic playback controls, and a real-time audio visualizer.

## Development

```bash
swift build        # Build
make run           # Build, codesign, and launch as Ditty.app
open Package.swift # Open in Xcode
```

No tests currently. macOS 14.2+ required. The app needs Automation permission to control Music.app, and Screen & System Audio Recording permission for the visualizer. The app **must** be launched via `open Ditty.app` (or `make run`), not by running the binary directly — TCC silently denies audio capture to bare binaries.

Code signing uses a local `DittyDev` self-signed certificate. Create it once via Keychain Access or openssl (see `docs/plans/2026-02-20-audio-tap-fix-design.md`).

## Architecture

- **SwiftUI** app with Swift Package Manager (single executable target)
- **AppleScript bridge** for Music.app communication — no private APIs, no MusicKit
- **NSPanel-style floating window** via `AppDelegate` in `App.swift` (sets `window.level = .floating`)
- **Polling model**: `MusicBridge` polls Music.app every 1 second via `Timer`. There is no event/notification API available from Music.app. Control actions (play/pause, next, previous) trigger an immediate re-poll after 300ms.

## Key Files

- `Sources/MusicController/MusicBridge.swift` — All AppleScript interaction. Uses `||`-delimited string responses parsed into `TrackInfo`. Artwork fetched separately as raw data.
- `Sources/MusicController/ContentView.swift` — The player UI. Owns the `MusicBridge` instance as `@StateObject`. Handles float/pin toggle.
- `Sources/MusicController/AudioAnalyzer.swift` — Core Audio Process Tap for real-time audio visualization. Taps Music.app's audio output directly (no microphone). Uses `CATapDescription` + tap-only aggregate device (no sub-devices) + IO proc callback. Reads format from `kAudioTapPropertyFormat`. FFT via vDSP with log-frequency band mapping, adaptive normalization, and high-frequency boost.
- `Sources/MusicController/App.swift` — App entry point and `AppDelegate` for floating window setup.

## Scope

- **In scope**: Current track display, basic playback controls, floating window
- **Out of scope**: Queue/up-next, library browsing, playlist management, streaming
