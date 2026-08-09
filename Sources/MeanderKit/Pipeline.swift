import Foundation

/// Latency instrumentation. GUI apps launched via `open` send stdout to
/// /dev/null, and the unified log store isn't readable in every dev environment,
/// so we append plain lines to a file we can always `cat`:
///   ~/Library/Logs/Meander-latency.log
public enum LatencyLog {
    public static let fileURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Meander-latency.log")

    public static func record(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

/// Orchestrates one dictation: record -> transcribe -> clean. UI-agnostic, so the
/// app layer only deals with start/stop and the final string (and pasting it).
public final class Pipeline {
    private let recorder: Recorder
    private let transcriber: Transcriber
    private let settings: Settings

    public init(transcriber: Transcriber, settings: Settings = .shared) {
        self.transcriber = transcriber
        self.settings = settings
        self.recorder = Recorder(settings: settings)
    }

    public var isRecording: Bool { recorder.isRecording }

    /// Whether the active engine supports live partial transcription.
    public var supportsStreaming: Bool { transcriber is StreamingTranscriber }

    /// Live input loudness (0...1) for UI meters, forwarded from the recorder.
    /// Set once; applies to both streaming and batch recording. Called on the
    /// audio thread, so hop to the main actor before touching UI state.
    public var onAudioLevel: ((Float) -> Void)? {
        didSet { recorder.onLevel = onAudioLevel }
    }

    /// Live frequency spectrum (relative band magnitudes, 0...1) for UI meters,
    /// forwarded from the recorder. Called on the audio thread.
    public var onAudioSpectrum: (([Float]) -> Void)? {
        didSet { recorder.onSpectrum = onAudioSpectrum }
    }

    public func startRecording() throws {
        try recorder.start()
    }

    // MARK: Streaming (live partials)

    /// Starts recording and streams audio into the transcriber, calling `onPartial`
    /// with the growing transcript as it decodes. Falls back to a plain recording
    /// if the engine isn't streaming-capable.
    public func startStreaming(onPartial: @escaping @Sendable (String) -> Void) async throws {
        guard let streaming = transcriber as? StreamingTranscriber else {
            try recorder.start()
            return
        }
        await streaming.beginStream { onPartial(TranscriptSanitizer.sanitize($0)) }
        recorder.onSamples = { samples in streaming.feed(samples) }
        do {
            try recorder.start()
        } catch {
            recorder.onSamples = nil
            _ = try? await streaming.finishStream()
            throw error
        }
    }

    /// Stops a streaming session, finishes decoding, and returns the cleaned text.
    /// `target` describes the app being dictated into (bundle id, name, focused
    /// window title), used to pick a formatting profile and inform LLM cleanup.
    public func stopStreamingAndProcess(target: DictationTarget? = nil) async throws -> String {
        recorder.onSamples = nil
        _ = recorder.stop()
        guard let streaming = transcriber as? StreamingTranscriber else { return "" }

        let raw = try await streaming.finishStream()
        let trimmed = Self.sanitize(raw)
        guard !trimmed.isEmpty else { return "" }

        return await clean(trimmed, target: target)
    }

    /// Stops recording, transcribes, and cleans using the currently selected
    /// provider. Returns "" if nothing usable was captured. Cleanup failures
    /// degrade gracefully: selected provider -> on-device cleanup -> raw text.
    public func stopAndProcess(target: DictationTarget? = nil) async throws -> String {
        let samples = recorder.stop()
        guard !samples.isEmpty else { return "" }

        let language = settings.effectiveLanguage
        let transcribeStart = DispatchTime.now()
        let raw = try await transcriber.transcribe(samples: samples, language: language)
        let transcribeMs = Self.elapsedMs(since: transcribeStart)
        let audioMs = Double(samples.count) / 16_000 * 1_000
        LatencyLog.record(String(
            format: "audio %.0fms · transcribe %.0fms (RTF %.2f)",
            audioMs, transcribeMs, audioMs > 0 ? transcribeMs / audioMs : 0
        ))
        let trimmed = Self.sanitize(raw)
        guard !trimmed.isEmpty else { return "" }

        return await clean(trimmed, target: target)
    }

    /// Strips the engine's control tokens before any layer treats them as words,
    /// and logs when there were any: a transcript containing them is a failed
    /// decode, and the log is the only place that shows it once the text is gone.
    private static func sanitize(_ raw: String) -> String {
        let text = TranscriptSanitizer.sanitize(raw)
        if TranscriptSanitizer.containsControlTokens(raw) {
            LatencyLog.record(
                "transcript: control tokens stripped (\(raw.count)→\(text.count) chars)"
            )
        }
        return text
    }

    /// Cleans transcript text using the formatting profile for the destination app
    /// and the selected provider. Failures degrade gracefully: selected provider
    /// -> on-device cleanup -> raw text.
    private func clean(_ text: String, target: DictationTarget?) async -> String {
        let language = settings.effectiveLanguage
        let profile = FormattingProfiles.resolve(target: target, settings: settings)
        var prepared = applyCommandMode(to: text, language: language)

        // Code destinations are inserted verbatim — never reshaped, never sent to
        // a cloud provider.
        if profile.style == .code { return prepared }

        // Phonetic dictionary pass runs before cleanup so every provider (including
        // fully on-device) sees "Karan Johar" instead of "current johar". Learned
        // mistakes ride along, so a mishearing the user has already fixed once is
        // repaired exactly rather than re-guessed phonetically.
        prepared = VocabularyCorrector.correct(prepared, book: settings.vocabularyBook)

        let cleaner = CleanupFactory.make(
            settings: settings,
            profile: profile,
            destination: DestinationDetector.displayName(for: target)
        )
        var result: String
        let cleanupStart = DispatchTime.now()
        do {
            result = try await cleaner.clean(prepared, language: language)
            LatencyLog.record(String(
                format: "cleanup %.0fms (%@, %d→%d chars)",
                Self.elapsedMs(since: cleanupStart), cleaner.id, prepared.count, result.count
            ))
        } catch {
            result = (try? await DeterministicCleanup().clean(prepared, language: language)) ?? prepared
            LatencyLog.record(String(
                format: "cleanup %.0fms (%@ FAILED → deterministic fallback)",
                Self.elapsedMs(since: cleanupStart), cleaner.id
            ))
        }

        if profile.style == .casual {
            result = FormattingProfiles.applyCasualTrim(result)
        }
        return result
    }

    /// Rewrites spoken commands ("new line", "comma"…) before cleanup when the
    /// feature is enabled. Skipped for Indic scripts since the commands are English.
    private func applyCommandMode(to text: String, language: Language) -> String {
        guard settings.commandModeEnabled else { return text }
        let isIndic = language.script == .indic
            || (language.isAuto && DeterministicCleanup.containsIndic(text))
        guard !isIndic else { return text }
        return CommandProcessor().process(text)
    }

    /// Discard an in-progress recording without processing it.
    public func cancel() {
        _ = recorder.stop()
    }

    /// Milliseconds elapsed since `start`, for the `[Latency]` instrumentation.
    private static func elapsedMs(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}
