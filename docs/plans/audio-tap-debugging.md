# Audio Tap Debugging Notes

**STATUS: RESOLVED** — See solution below. Full session log at `logs/02-20-2026-1300.md`.

## Problem

The Core Audio Process Tap connects to Music.app successfully — tap creation, aggregate device, IO proc all return `noErr` — but audio buffers contain all zeros (silence). The IO callback fires at ~100Hz with 512 stereo frames per callback, but RMS is always 0.0.

## Solution

The silence had **two root causes** working together:

### 1. App must be launched via `open` (LaunchServices), not by running the binary directly

TCC for Screen & System Audio Recording only grants permission when the app is launched through LaunchServices (`open Ditty.app` or `make run`). Running the binary directly (`./Ditty.app/Contents/MacOS/Ditty`) causes TCC to silently deliver zero-filled buffers — no errors, no feedback.

### 2. Ad-hoc code signing invalidated TCC grants

`codesign --sign -` produces a different signature every rebuild. TCC caches grants by signature, so each rebuild silently invalidated the previous grant. Fixed by creating a stable `DittyDev` self-signed certificate.

### Additional fixes applied (correctness, not root cause)

- Removed output sub-device from aggregate (tap-only, SoundPusher pattern)
- Read format from `kAudioTapPropertyFormat` on tap ID instead of aggregate device
- Rewrote FFT visualization with adaptive normalization for tap signal levels

## What Was Ruled Out

- **DRM** — Apple Music streaming content works fine with process taps
- **AudioTee two-step approach** — Creating empty aggregate then adding tap via property fails with `AudioDeviceStart` error 1852797029
- **Entitlements** — `com.apple.security.device.audio-input` is necessary but not sufficient alone
- **Sub-device config** — Both with and without sub-devices produce callbacks; the silence was TCC, not routing

## Key TCC Facts

- `tccutil reset ScreenCapture` is the correct service (NOT `AudioCapture`)
- The `[aud]` indicator in ControlCenter appears even when TCC is silently denying access
- Enabling Ditty in System Settings > Privacy > Screen & System Audio Recording is required
- Permission only works when launched via LaunchServices (`open`), not direct binary execution

## Reference Implementations

- [AudioCap](https://github.com/insidegui/AudioCap) — BSD-2, most complete Swift reference
- [AudioTee](https://github.com/makeusabrew/audiotee) — modular CLI tool
- [SoundPusher](https://codeberg.org/q-p/SoundPusher) — C++, tap-only aggregate device (no sub-devices)
- [audiograb](https://github.com/obsfx/audiograb) — simple CLI recorder with entitlements
- [Core Audio Taps for Dummies](https://www.maven.de/2025/04/coreaudio-taps-for-dummies/) — best writeup of TCC/permission gotchas
