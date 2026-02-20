import AVFoundation
import Accelerate
import CoreAudio
import AppKit

/// Taps Music.app's audio output via Core Audio Process Tap API (macOS 14.2+).
/// Uses a tap-only aggregate device (no sub-devices) and reads format from the tap itself.
class AudioAnalyzer: ObservableObject {
    @Published var bands: [Float] = Array(repeating: 0, count: 64)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var retryTimer: Timer?
    private var recentPeak: Float = 0.001

    func start() {
        guard ioProcID == nil else { return }
        tryConnect()
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        teardown()
        DispatchQueue.main.async {
            self.bands = Array(repeating: 0, count: 64)
        }
    }

    deinit {
        retryTimer?.invalidate()
        if #available(macOS 14.2, *) {
            if let procID = ioProcID {
                AudioDeviceStop(aggregateDeviceID, procID)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            }
            if aggregateDeviceID != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            }
            if tapID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }

    // MARK: - Connection

    private func tryConnect() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if self.connectToMusicApp() {
                DispatchQueue.main.async {
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                }
            } else if self.retryTimer == nil {
                DispatchQueue.main.async {
                    self.retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                        self?.tryConnect()
                    }
                }
            }
        }
    }

    // MARK: - Process Tap Setup

    private func connectToMusicApp() -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        guard ioProcID == nil else { return true }

        // 1. Find Music.app PID
        guard let musicApp = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.Music" }) else {
            return false
        }

        // 2. Translate PID → AudioObjectID
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var pid = musicApp.processIdentifier
        var pidAddress = propertyAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var objectIDSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let pidResult = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &pidAddress,
            UInt32(MemoryLayout<pid_t>.size), &pid,
            &objectIDSize, &processObjectID
        )
        guard pidResult == noErr, processObjectID != kAudioObjectUnknown else { return false }

        // 3. Create process tap
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDesc.uuid = UUID()
        tapDesc.muteBehavior = .unmuted
        tapDesc.isPrivate = true

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(tapDesc, &newTapID) == noErr else { return false }
        tapID = newTapID

        // 4. Create aggregate device with tap (no sub-devices)
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
        var newDeviceID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newDeviceID) == noErr else {
            cleanup(tap: true)
            return false
        }
        aggregateDeviceID = newDeviceID

        // 5. Wait for device readiness
        for _ in 0..<20 {
            if isDeviceAlive(aggregateDeviceID) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }

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

        // 7. Create IO proc
        let ioQueue = DispatchQueue(label: "com.shaun.Ditty.audio-io", qos: .userInteractive)
        var newProcID: AudioDeviceIOProcID?

        let ioResult = AudioDeviceCreateIOProcIDWithBlock(
            &newProcID,
            aggregateDeviceID,
            ioQueue
        ) { [weak self] _, inInputData, _, _, _ in
            guard let self else { return }

            let bufferList = inInputData.pointee
            let buf = bufferList.mBuffers
            guard let data = buf.mData, buf.mDataByteSize > 0 else { return }

            let floatPtr = data.assumingMemoryBound(to: Float.self)
            let totalFloats = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            let channelCount = max(1, Int(buf.mNumberChannels))
            let frameCount = totalFloats / channelCount

            // Extract left channel (stride by channelCount for interleaved)
            var samples = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                samples[i] = floatPtr[i * channelCount]
            }

            let newBands = Self.fftBands(from: samples, peak: &self.recentPeak)

            DispatchQueue.main.async {
                for i in 0..<self.bands.count {
                    let target = i < newBands.count ? newBands[i] : 0
                    if target > self.bands[i] {
                        // Instant attack — snap to peaks
                        self.bands[i] = target
                    } else {
                        // Quick decay — keeps things lively
                        self.bands[i] = self.bands[i] * 0.7 + target * 0.3
                    }
                }
            }
        }

        guard ioResult == noErr, let newProcID else {
            cleanup(tap: true, device: true)
            return false
        }
        ioProcID = newProcID

        // 8. Start
        guard AudioDeviceStart(aggregateDeviceID, newProcID) == noErr else {
            cleanup(tap: true, device: true, ioProc: true)
            return false
        }

        return true
    }

    // MARK: - Helpers

    private func propertyAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func isDeviceAlive(_ deviceID: AudioObjectID) -> Bool {
        var address = propertyAddress(kAudioDevicePropertyDeviceIsAlive)
        var isAlive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isAlive) == noErr
            && isAlive == 1
    }

    private func cleanup(tap: Bool = false, device: Bool = false, ioProc: Bool = false) {
        guard #available(macOS 14.2, *) else { return }
        if ioProc, let procID = ioProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            ioProcID = nil
        }
        if device, aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tap, tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func teardown() {
        cleanup(tap: true, device: true, ioProc: true)
    }

    // MARK: - FFT

    static func fftBands(from samples: [Float], peak: inout Float) -> [Float] {
        let bandCount = 64
        let n = 4096
        let halfN = n / 2

        var buffer = [Float](repeating: 0, count: n)
        let count = min(samples.count, n)
        for i in 0..<count { buffer[i] = samples[i] }

        // Hann window
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(buffer, 1, window, 1, &buffer, 1, vDSP_Length(n))

        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return Array(repeating: 0, count: bandCount)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = [Float](repeating: 0, count: halfN)
        var imag = [Float](repeating: 0, count: halfN)

        real.withUnsafeMutableBufferPointer { realBuf in
            imag.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(
                    realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)

                buffer.withUnsafeBufferPointer { bufPtr in
                    bufPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) {
                        cplx in
                        vDSP_ctoz(cplx, 2, &split, 1, vDSP_Length(halfN))
                    }
                }

                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, realBuf.baseAddress!, 1, vDSP_Length(halfN))
            }
        }

        // Square root to get amplitude (not power) — less spiky, more musical
        var magnitudes = [Float](repeating: 0, count: halfN)
        var sqrtCount = Int32(halfN)
        vvsqrtf(&magnitudes, real, &sqrtCount)

        // Log-frequency band mapping (perceptual, not squared)
        // Maps ~20Hz–20kHz across 64 bands using log scale
        let minFreq: Float = 30
        let maxFreq: Float = min(20000, Float(48000) / 2)
        let logMin = log2(minFreq)
        let logMax = log2(maxFreq)
        let binHz = Float(48000) / Float(n)

        var bands = [Float](repeating: 0, count: bandCount)
        for i in 0..<bandCount {
            let f0 = pow(2, logMin + (logMax - logMin) * Float(i) / Float(bandCount))
            let f1 = pow(2, logMin + (logMax - logMin) * Float(i + 1) / Float(bandCount))
            let lo = max(1, Int(f0 / binHz))
            let hi = max(lo + 1, min(halfN, Int(f1 / binHz)))

            // Use peak (max) of bin range, not average — more reactive
            var bandMax: Float = 0
            for j in lo..<hi {
                bandMax = max(bandMax, magnitudes[j])
            }
            bands[i] = bandMax
        }

        // Adaptive normalization: track recent peak, normalize against it
        var currentMax: Float = 0
        vDSP_maxv(bands, 1, &currentMax, vDSP_Length(bandCount))

        // Slowly chase the peak — rises fast, decays slowly
        if currentMax > peak {
            peak = peak * 0.3 + currentMax * 0.7
        } else {
            peak = peak * 0.995 + currentMax * 0.005
        }
        let normFactor = 1.0 / max(peak, 0.0001)

        for i in 0..<bandCount {
            // Normalize against adaptive peak
            var val = bands[i] * normFactor
            // Boost higher bands — high frequencies have less energy naturally
            let t = Float(i) / Float(bandCount - 1)
            let boost: Float = 1.0 + t * 2.5  // 1x at low end, 3.5x at high end
            val *= boost
            // Power curve to boost detail
            val = pow(val, 0.7)
            bands[i] = min(1, val)
        }

        return bands
    }
}
