import AVFoundation
import Accelerate
import CoreAudio
import AppKit

/// Taps Music.app's audio output via Core Audio Process Tap API (macOS 14.2+).
///
/// STATUS: The tap pipeline connects successfully (process tap → aggregate device → IO proc)
/// and the IO callback fires, but audio buffers contain silence. Suspected TCC/entitlement
/// issue — see docs/plans/audio-tap-debugging.md for investigation notes.
class AudioAnalyzer: ObservableObject {
    @Published var bands: [Float] = Array(repeating: 0, count: 64)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var retryTimer: Timer?

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

        // 4. Get system output device UID (needed as sub-device for the aggregate)
        var outputDeviceID = AudioObjectID(kAudioObjectUnknown)
        var outputProp = propertyAddress(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var outputSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &outputProp, 0, nil, &outputSize, &outputDeviceID
        ) == noErr else {
            cleanup(tap: true)
            return false
        }

        var outputUIDProp = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var outputUID: CFString = "" as CFString
        var outputUIDSize = UInt32(MemoryLayout<CFString>.stride)
        guard withUnsafeMutablePointer(to: &outputUID, { ptr in
            AudioObjectGetPropertyData(outputDeviceID, &outputUIDProp, 0, nil, &outputUIDSize, ptr)
        }) == noErr else {
            cleanup(tap: true)
            return false
        }

        // 5. Create aggregate device with output sub-device and tap
        let tapUUIDString = tapDesc.uuid.uuidString
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MusicControllerTap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
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

        // 6. Wait for device readiness
        for _ in 0..<20 {
            if isDeviceAlive(aggregateDeviceID) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }

        // 7. Read stream format (retry a few times — device may need a moment)
        var formatProp = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamDesc = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)

        var gotFormat = false
        for _ in 0..<5 {
            if AudioObjectGetPropertyData(
                aggregateDeviceID, &formatProp, 0, nil, &formatSize, &streamDesc
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

        // 8. Create IO proc
        let ioQueue = DispatchQueue(label: "com.shaun.MusicController.audio-io", qos: .userInteractive)
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
            let newBands = Self.fftBands(from: samples)

            DispatchQueue.main.async {
                for i in 0..<self.bands.count {
                    let target = i < newBands.count ? newBands[i] : 0
                    if target > self.bands[i] {
                        self.bands[i] = self.bands[i] * 0.1 + target * 0.9
                    } else {
                        self.bands[i] = self.bands[i] * 0.75 + target * 0.25
                    }
                }
            }
        }

        guard ioResult == noErr, let newProcID else {
            cleanup(tap: true, device: true)
            return false
        }
        ioProcID = newProcID

        // 9. Start
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

    static func fftBands(from samples: [Float]) -> [Float] {
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

        var magnitudes = real

        // To dB (power → dB with ref=1)
        var ref: Float = 1
        vDSP_vdbcon(magnitudes, 1, &ref, &magnitudes, 1, vDSP_Length(halfN), 0)

        // Frequency weighting — music is naturally bass-heavy, so attenuate
        // low bins to keep the visualizer dynamic across the full spectrum.
        // Gentle sqrt curve: lowest bin → 0.25x, highest → 1.0x
        for i in 0..<halfN {
            let t = Float(i + 1) / Float(halfN)
            magnitudes[i] *= (0.25 + 0.75 * sqrt(t))
        }

        // Normalize: process tap delivers full-scale digital audio,
        // so dB range is roughly 10..60 rather than the -60..0 a mic sees
        for i in 0..<halfN {
            magnitudes[i] = max(0, min(1, (magnitudes[i] - 10) / 50))
        }

        // Squared frequency mapping — each band gets unique bins
        var bands = [Float](repeating: 0, count: bandCount)
        for i in 0..<bandCount {
            let t0 = Float(i) / Float(bandCount)
            let t1 = Float(i + 1) / Float(bandCount)
            let lo = max(1, Int(t0 * t0 * Float(halfN)))
            let hi = max(lo + 1, min(halfN, Int(t1 * t1 * Float(halfN))))

            var sum: Float = 0
            for j in lo..<hi { sum += magnitudes[j] }
            bands[i] = sum / Float(hi - lo)
        }

        return bands
    }
}
