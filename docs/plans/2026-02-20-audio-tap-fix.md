# Audio Tap Fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix Ditty's silent audio tap so the visualizer receives real PCM data from Music.app.

**Architecture:** Three incremental fixes to the Core Audio Process Tap pipeline — stable code signing for TCC, tap-only aggregate device (no sub-devices), and reading format from the tap itself. Plus diagnostics and rename from "Music Controller" to "Ditty."

**Tech Stack:** Swift, Core Audio (`AudioHardwareCreateProcessTap`, `CATapDescription`), vDSP/Accelerate, SwiftUI

---

### Task 1: Create Self-Signed Certificate

This is a manual step the user performs in Keychain Access. Cannot be automated.

**Step 1: Create the certificate**

Open Keychain Access > Certificate Assistant > Create a Certificate:
- Name: `DittyDev`
- Identity Type: Self Signed Root
- Certificate Type: Code Signing
- Click Create

**Step 2: Verify it exists**

Run: `security find-identity -v -p codesigning | grep DittyDev`
Expected: One line showing the `DittyDev` identity

---

### Task 2: Update Makefile — Signing + Rename to Ditty

**Files:**
- Modify: `Makefile`

**Step 1: Update Makefile**

Replace the entire Makefile with:

```makefile
APP_NAME = Ditty
APP_DIR = $(APP_NAME).app
BUNDLE = $(APP_DIR)/Contents
BUILD_DIR = .build/release

.PHONY: build install clean run

build:
	swift build -c release

install: build
	mkdir -p "$(BUNDLE)/MacOS"
	cp $(BUILD_DIR)/MusicController "$(BUNDLE)/MacOS/"
	cp Info.plist "$(BUNDLE)/"
	codesign --force --sign "DittyDev" --entitlements entitlements.plist "$(APP_DIR)"
	@echo "Built $(APP_DIR)"

run: install
	open "$(APP_DIR)"

clean:
	swift package clean
	rm -rf "$(APP_DIR)"
```

Changes: `APP_NAME = Ditty`, `--sign "DittyDev"` instead of `--sign -`.

**Step 2: Verify**

Run: `make clean` (removes old "Music Controller.app")
Expected: Old app bundle removed

---

### Task 3: Update Info.plist — Rename to Ditty

**Files:**
- Modify: `Info.plist`

**Step 1: Update bundle name and descriptions**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MusicController</string>
    <key>CFBundleIdentifier</key>
    <string>com.shaun.Ditty</string>
    <key>CFBundleName</key>
    <string>Ditty</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.2</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Ditty needs to communicate with Music.app to display track information and control playback.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Ditty captures audio from Music.app to display a real-time visualizer.</string>
</dict>
</plist>
```

Changes: `CFBundleIdentifier` → `com.shaun.Ditty`, `CFBundleName` → `Ditty`, updated description strings.

---

### Task 4: Update App.swift — Rename menu items

**Files:**
- Modify: `Sources/Ditty/App.swift:10,67,71`

**Step 1: Rename struct and menu strings**

Line 10: `MusicControllerApp` → `DittyApp`
Line 67: `"About Music Controller"` → `"About Ditty"`
Line 71: `"Quit Music Controller"` → `"Quit Ditty"`

---

### Task 5: Fix Aggregate Device — Remove Sub-Devices

This is the core audio fix. Remove the output device lookup and create a tap-only aggregate.

**Files:**
- Modify: `Sources/Ditty/AudioAnalyzer.swift:105-149`

**Step 1: Delete the output device UID lookup (lines 105-129)**

Remove everything from `// 4. Get system output device UID` through the closing brace of the `withUnsafeMutablePointer` guard.

**Step 2: Replace the aggregate device creation (lines 131-149)**

Replace with tap-only aggregate:

```swift
        // 4. Create aggregate device with tap only (no sub-devices)
        let tapUUIDString = tapDesc.uuid.uuidString
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "DittyTap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUUIDString,
                ]
            ],
        ]
```

No `kAudioAggregateDeviceMainSubDeviceKey`. No `kAudioAggregateDeviceSubDeviceListKey`. Just the tap.

---

### Task 6: Fix Format Source — Read from Tap

**Files:**
- Modify: `Sources/Ditty/AudioAnalyzer.swift` (the format-reading section, currently lines 163-186)

**Step 1: Replace format read**

Replace the current format-reading block with reading from the tap ID using `kAudioTapPropertyFormat`:

```swift
        // 6. Read tap format
        var formatProp = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamDesc = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)

        var gotFormat = false
        for _ in 0..<5 {
            if AudioObjectGetPropertyData(
                tapID, &formatProp, 0, nil, &formatSize, &streamDesc
            ) == noErr, streamDesc.mSampleRate > 0 {
                gotFormat = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        guard gotFormat, let _ = AVAudioFormat(streamDescription: &streamDesc) else {
            cleanup(tap: true, device: true)
            return false
        }
```

Key changes: `kAudioTapPropertyFormat` instead of `kAudioDevicePropertyStreamFormat`, `tapID` instead of `aggregateDeviceID`, scope is `Global` not `Input`.

---

### Task 7: Add Diagnostics

**Files:**
- Modify: `Sources/Ditty/AudioAnalyzer.swift`

**Step 1: Add import and callback counter**

Add `import os.log` at top of file.

Add a private property:

```swift
private var callbackCount = 0
private var loggedFirstAudio = false
```

**Step 2: Log tap format after successful connect**

After the format guard succeeds (end of Task 6's code), add:

```swift
        os_log(.info, "Ditty: tap connected — %.0fHz, %d ch, %d bit",
               streamDesc.mSampleRate,
               streamDesc.mChannelsPerFrame,
               streamDesc.mBitsPerChannel)
```

**Step 3: Add diagnostics to the IO callback**

Inside the IO proc block, after extracting samples, add RMS check:

```swift
            // Diagnostics
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameCount))

            let count = OSAtomicIncrement32(&self.callbackCount)
            if rms > 0 && !self.loggedFirstAudio {
                self.loggedFirstAudio = true
                os_log(.info, "Ditty: audio flowing (RMS %.6f at callback #%d)", rms, count)
            }
            if count == 200 && !self.loggedFirstAudio {
                os_log(.error, "Ditty: still silent after 200 callbacks — check System Settings > Privacy > Screen & System Audio Recording")
            }
```

Note: `callbackCount` needs to be `Int32` for `OSAtomicIncrement32`, and add `import Darwin` for atomics (or just use a simple non-atomic counter since the IO queue is serial).

**Step 4: Update the ioQueue label**

Line 189: `"com.shaun.MusicController.audio-io"` → `"com.shaun.Ditty.audio-io"`

---

### Task 8: Update Doc Comment

**Files:**
- Modify: `Sources/Ditty/AudioAnalyzer.swift:6-10`

**Step 1: Update the class doc comment**

Replace:
```swift
/// Taps Music.app's audio output via Core Audio Process Tap API (macOS 14.2+).
///
/// STATUS: The tap pipeline connects successfully (process tap → aggregate device → IO proc)
/// and the IO callback fires, but audio buffers contain silence. Suspected TCC/entitlement
/// issue — see docs/plans/audio-tap-debugging.md for investigation notes.
```

With:
```swift
/// Taps Music.app's audio output via Core Audio Process Tap API (macOS 14.2+).
/// Uses a tap-only aggregate device (no sub-devices) and reads format from the tap itself.
```

---

### Task 9: Reset TCC and Build

**Step 1: Reset TCC permissions**

Run: `tccutil reset AudioCapture`

This clears any stale/confused grants from previous ad-hoc-signed builds.

**Step 2: Build and install**

Run: `make run`
Expected: App builds, codesigns with DittyDev identity, opens as "Ditty.app"

**Step 3: Approve permission**

When the system dialog appears, approve "Screen & System Audio Recording" for Ditty.

**Step 4: Verify in Console.app or terminal**

Look for log output:
- `Ditty: tap connected — 48000Hz, 2 ch, 32 bit` (or similar)
- `Ditty: audio flowing (RMS ... at callback #N)` (confirms fix worked)
- If after ~2s: `Ditty: still silent after 200 callbacks` (TCC still blocking — investigate further)

---

### Task 10: Commit

**Step 1: Stage and commit all changes**

```bash
git add Makefile Info.plist entitlements.plist \
  Sources/Ditty/AudioAnalyzer.swift \
  Sources/Ditty/App.swift \
  docs/plans/2026-02-20-audio-tap-fix-design.md \
  docs/plans/2026-02-20-audio-tap-fix.md
git commit -m "Fix silent audio tap: stable signing, tap-only aggregate, tap format

- Replace ad-hoc codesigning with stable DittyDev certificate
- Remove output sub-device from aggregate (tap-only, SoundPusher pattern)
- Read format from kAudioTapPropertyFormat on tap instead of aggregate device
- Add diagnostic logging (tap format, first audio RMS, silence warning)
- Rename from Music Controller to Ditty"
```
