# Audio Tap Fix — Design

## Problem

Ditty's Core Audio Process Tap connects to Music.app without errors, but delivers silent buffers (all zeros). Root cause analysis identified three compounding issues.

## Root Causes

### 1. Ad-Hoc Code Signing Invalidates TCC Grants (Primary)

The Makefile uses `codesign --sign -` (ad-hoc). Every rebuild produces a different code signature. TCC identifies apps by signature, so each rebuild silently invalidates the previous permission grant. The system doesn't re-prompt — it just delivers silence. All API calls return `noErr`, making this invisible without knowing to look for it.

### 2. Sub-Device in Aggregate Device

The aggregate device includes the system output device as a sub-device (AudioCap pattern). The SoundPusher author found this "confused matters." Every working open-source implementation (SoundPusher, audiograb, MiniMeters/sudara gist) uses a tap-only aggregate with no sub-devices.

### 3. Format Read from Wrong Source

Format is read via `kAudioDevicePropertyStreamFormat` on the aggregate device. Should use `kAudioTapPropertyFormat` on the tap's AudioObjectID — this is what the tap actually delivers.

## Solution

### Approach: Incremental Fix

Fix issues in priority order. Even if signing alone resolves silence, apply all three fixes for correctness and stability.

### Changes

**Code Signing (Makefile)**
- Create self-signed `DittyDev` certificate in Keychain Access
- Update Makefile: `--sign "DittyDev"` instead of `--sign -`
- Reset TCC after first build: `tccutil reset AudioCapture`

**Aggregate Device (AudioAnalyzer.swift)**
- Remove output device UID lookup (~20 lines deleted)
- Remove `kAudioAggregateDeviceMainSubDeviceKey` from aggregate dict
- Remove `kAudioAggregateDeviceSubDeviceListKey` from aggregate dict
- Keep only: tap list, tap auto-start, private, name, UID

**Tap Format (AudioAnalyzer.swift)**
- Read `kAudioTapPropertyFormat` from `tapID` instead of `kAudioDevicePropertyStreamFormat` from `aggregateDeviceID`

**Diagnostics (AudioAnalyzer.swift)**
- Log tap format on successful connect (sample rate, channels, bits)
- Log first non-zero RMS (confirms audio flowing)
- Warn if still silent after ~200 callbacks (~2 seconds)

**Rename to Ditty**
- Info.plist: bundle name, display name
- Makefile: app directory name
- Package.swift: target/product name if needed
- AudioAnalyzer: aggregate device name string
- NSAudioCaptureUsageDescription: update copy

## References

- [CoreAudio Taps for Dummies](https://www.maven.de/2025/04/coreaudio-taps-for-dummies/) — TCC/signing gotchas
- [SoundPusher](https://codeberg.org/q-p/SoundPusher) — tap-only aggregate pattern
- [AudioCap](https://github.com/insidegui/AudioCap) — `kAudioTapPropertyFormat` usage
- [AudioTee](https://github.com/makeusabrew/audiotee) — clean Swift reference
