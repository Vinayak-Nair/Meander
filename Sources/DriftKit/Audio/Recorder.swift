import AVFoundation
import AudioUnit
import CoreAudio

/// Captures microphone audio and returns 16 kHz mono Float samples, the format
/// WhisperKit's `transcribe(audioArray:)` expects. No temp files involved.
///
/// Capture runs on an AudioQueue by default, for both the automatic device and
/// an explicitly selected microphone: an input queue starts much faster than an
/// AVAudioEngine graph, so the mic is hot almost as soon as the hotkey goes
/// down. The engine path is kept as an automatic fallback for devices or
/// drivers the queue can't start on.
public final class Recorder {
    public enum RecorderError: Error { case engineFailedToStart }

    private enum Backend { case audioQueue, engine }

    private let engine = AVAudioEngine()
    private let audioQueue = AudioQueueCapture()
    private var activeBackend: Backend?
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let targetSampleRate: Double = 16_000
    private let lock = NSLock()
    private let settings: Settings

    public private(set) var isRecording = false

    /// Optional live tap: called with each freshly converted 16 kHz mono chunk as
    /// it's captured, in addition to being accumulated for the batch result. Used
    /// by streaming transcription. Called on the audio thread.
    public var onSamples: (([Float]) -> Void)?

    /// Optional live level meter: called with a perceptual 0...1 loudness for each
    /// captured chunk, for driving a reactive waveform. Called on the audio thread.
    public var onLevel: ((Float) -> Void)?

    /// Optional live frequency spectrum: called with the relative band magnitudes
    /// (0...1) of the latest audio for a spectrum visualization. Audio thread.
    public var onSpectrum: (([Float]) -> Void)?
    private let spectrum = SpectrumAnalyzer()

    public init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Begins capture. Throws if no capture path can start (e.g. mic denied).
    public func start() throws {
        guard !isRecording else { return }
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        if settings.recorderUsesAudioQueue, startAudioQueue() {
            activeBackend = .audioQueue
            isRecording = true
            LatencyLog.record("recorder start · backend=audioQueue · device=\(selectedDeviceUID() ?? "systemDefault")")
            return
        }

        try startEngine()
        activeBackend = .engine
        isRecording = true
        LatencyLog.record("recorder start · backend=engine (queue unavailable or disabled)")
    }

    /// Stops capture and returns the captured samples. Returns an empty array if
    /// the clip was too short to be meaningful (< 0.2 s).
    public func stop() -> [Float] {
        guard isRecording else { return [] }
        switch activeBackend {
        case .audioQueue:
            audioQueue.stop()
        case .engine, nil:
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        activeBackend = nil
        isRecording = false

        lock.lock(); let captured = samples; lock.unlock()

        // Diagnostic: report what capture actually produced. A near-zero peak
        // with a healthy sample count means the queue ran but delivered silence
        // (typically a missing microphone permission for this app), as opposed to
        // no samples at all (capture never started).
        var peak: Float = 0
        for s in captured { let a = abs(s); if a > peak { peak = a } }
        LatencyLog.record(String(
            format: "recorder stop · samples=%d (%.2fs) · peak=%.4f%@",
            captured.count, Double(captured.count) / targetSampleRate, peak,
            peak < 0.0009 ? " · SILENT (check mic permission)" : ""
        ))

        guard captured.count > Int(targetSampleRate * 0.2) else { return [] }
        return captured
    }

    // MARK: AudioQueue path (default)

    private func startAudioQueue() -> Bool {
        audioQueue.onChunk = { [weak self] chunk in self?.process(chunk: chunk) }
        do {
            try audioQueue.start(deviceUID: selectedDeviceUID())
            return true
        } catch {
            return false
        }
    }

    /// UID for the queue's device selection: nil means the system default input,
    /// used both for "Automatic" and when the remembered device is unplugged
    /// (matching the engine path, which also falls back to the default then).
    private func selectedDeviceUID() -> String? {
        let selection = settings.inputDeviceID
        guard selection != AudioInputDevice.systemDefaultID else { return nil }
        guard AudioInputDevices.deviceID(for: selection) != nil else { return nil }
        return selection
    }

    // MARK: AVAudioEngine path (fallback)

    private func startEngine() throws {
        let input = engine.inputNode
        try applySelectedInputDevice(to: input)
        let inputFormat = input.outputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { throw RecorderError.engineFailedToStart }

        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer: buffer, outputFormat: outputFormat)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.engineFailedToStart
        }
    }

    private func append(buffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) {
        guard let converter else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if error != nil { return }

        guard let channel = out.floatChannelData?[0] else { return }
        let frames = Int(out.frameLength)
        process(chunk: Array(UnsafeBufferPointer(start: channel, count: frames)))
    }

    // MARK: Shared chunk handling

    /// Accumulates a 16 kHz mono chunk and feeds the live taps. Both capture
    /// paths land here, on their respective audio threads.
    private func process(chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
        onSamples?(chunk)

        if let onLevel {
            var sumSquares: Float = 0
            for s in chunk { sumSquares += s * s }
            let rms = (sumSquares / Float(chunk.count)).squareRoot()
            onLevel(Recorder.normalizedLevel(rms: rms))
        }

        if let onSpectrum, let bands = spectrum.process(chunk) {
            onSpectrum(bands)
        }
    }

    /// Maps RMS amplitude to a perceptual 0...1 level. A quiet room sits at 0;
    /// normal speech fills most of the range. Tuned on a dB scale so the meter
    /// tracks perceived loudness rather than raw amplitude.
    private static func normalizedLevel(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        let floor: Float = -52    // at/below this we treat the input as silent
        let ceiling: Float = -22  // at/above this the meter is full (normal speech)
        let norm = min(1, max(0, (db - floor) / (ceiling - floor)))
        // Gentle gamma so soft and normal speech climb higher rather than hugging
        // the lower half of the range.
        return pow(norm, 0.7)
    }

    private func applySelectedInputDevice(to input: AVAudioInputNode) throws {
        guard let deviceID = AudioInputDevices.deviceID(for: settings.inputDeviceID) else { return }
        guard let audioUnit = input.audioUnit else { throw RecorderError.engineFailedToStart }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw RecorderError.engineFailedToStart }
    }
}
