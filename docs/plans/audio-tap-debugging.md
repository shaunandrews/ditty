# Audio Tap Debugging Notes

## Problem

The Core Audio Process Tap connects to Music.app successfully — tap creation, aggregate device, IO proc all return `noErr` — but audio buffers contain all zeros (silence). The IO callback fires at ~100Hz with 512 stereo frames per callback, but RMS is always 0.0.

## What Works

- `AudioHardwareCreateProcessTap` succeeds, returns valid tap ID
- `AudioHardwareCreateAggregateDevice` succeeds with output sub-device + tap
- `AudioDeviceCreateIOProcIDWithBlock` succeeds
- `AudioDeviceStart` succeeds
- IO callback fires consistently with valid buffer pointers and sizes
- Format reads correctly: 48000Hz, 2ch, 32bit, Float32, interleaved

## What We Verified

- Raw hex bytes of both INPUT and OUTPUT buffers: all `00`
- RMS at callbacks #10, #50, #200: always 0.0
- Ran from app bundle binary (not bare `swift run`) for correct TCC context
- Music.app confirmed playing audio
- Tried both aggregate device approaches:
  - AudioTee style: empty aggregate device, tap attached via `kAudioAggregateDevicePropertyTapList` property → silence
  - AudioCap style: output device as sub-device + tap in creation dictionary → silence

## Fixes Applied (Not Sufficient)

- Added `entitlements.plist` with `com.apple.security.device.audio-input`
- Updated Makefile to codesign with `--entitlements entitlements.plist`
- Reset TCC with `tccutil reset AudioCapture`
- User approved fresh permission dialog

## Remaining Theories

1. **TCC still not granting real access** — ad-hoc codesigning (`--sign -`) may produce different signatures each rebuild, invalidating TCC grants. May need a stable Developer ID or self-signed certificate.

2. **Aggregate device sub-device config** — SoundPusher's author found that including the output device as a sub-device "confused matters". Try creating aggregate with ONLY the tap (no sub-device list, no main sub-device key).

3. **Tap format mismatch** — AudioCap reads format from `kAudioTapPropertyFormat` on the tap ID, not `kAudioDevicePropertyStreamFormat` on the aggregate device. The IO proc might need the tap's native format for `AVAudioPCMBuffer` wrapping.

4. **AVAudioEngine approach** — Instead of raw IO proc, set the aggregate device as `AVAudioEngine.inputNode`'s device via `kAudioOutputUnitProperty_CurrentDevice`, then use `installTap(onBus:)`. This is closer to the original mic code and may handle routing differently.

5. **Music.app DRM** — Apple Music streaming content may have DRM that prevents process taps from capturing audio. If so, only locally-owned tracks would produce non-zero buffers. Test with a local MP3/AAC file imported into Music.app.

## Reference Implementations

- [AudioCap](https://github.com/insidegui/AudioCap) — BSD-2, most complete Swift reference
- [AudioTee](https://github.com/makeusabrew/audiotee) — modular CLI tool
- [SoundPusher](https://github.com/q-p/SoundPusher) — C++, tap-only aggregate device (no sub-devices)
- [audiograb](https://github.com/obsfx/audiograb) — simple CLI recorder with entitlements
- [Core Audio Taps for Dummies](https://www.maven.de/2025/04/coreaudio-taps-for-dummies/) — best writeup of TCC/permission gotchas
