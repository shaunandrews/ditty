# Music Controller

A minimal, floating Apple Music controller for macOS. Shows what's playing without the clutter.

## Overview

A lightweight SwiftUI app that displays the current track (song, artist, album art) with play/pause and skip controls. Can float above other windows or sit quietly on your desktop. Talks to Music.app via AppleScript.

## Quick Start

```bash
cd ~/Developer/Projects/music-controller
swift build
swift run
```

Or open `Package.swift` in Xcode.

## Features

- Current track: song title, artist, album artwork
- Play/pause and next track controls
- Always-on-top (floating) mode, toggleable
- Minimal, clean UI — shows what matters, nothing else

## Structure

```
music-controller/
├── Sources/MusicController/
│   ├── App.swift              # App entry point
│   ├── ContentView.swift      # Main player UI
│   ├── MusicBridge.swift      # AppleScript bridge to Music.app
│   └── WindowDelegate.swift   # Floating window behavior
├── Package.swift              # Swift Package Manager config
├── docs/                      # Documentation
└── README.md
```

## Requirements

- macOS 13+ (Ventura)
- Apple Music / Music.app
- Grants automation permission when first launched
