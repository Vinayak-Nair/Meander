import Foundation
import FluidAudio

/// FluidAudio backend using Parakeet TDT v3, NVIDIA's multilingual model. Drift
/// records full push-to-talk utterances, so each transcription gets a fresh
/// decoder state.
///
/// v3 infers its own output language from the acoustics, which on short phrases it
/// sometimes gets wrong, returning English speech transliterated into another
/// script. Passing `language` is what prevents that: FluidAudio's v3 decoder
/// checks every token against the declared language's script and swaps a
/// mismatched token for the best same-script candidate in the joint model's top-K,
/// inside the decode loop. Nothing downstream has to detect or repair anything.
///
/// The enforcement is v3-only, because only the v3 joint model emits the top-K
/// outputs the filter reads. On any other build `AsrManager` logs the hint and
/// ignores it, so the model version and this call are a single mechanism: see
/// `ModelManager.parakeetVersion`.
public final class FluidAudioTranscriber: Transcriber {
    private let asrManager: AsrManager
    /// Acoustic dictionary correction. Optional because it needs a second model:
    /// when it is absent, or its model is unavailable, transcription is exactly
    /// what it was before.
    private let booster: ParakeetVocabularyBooster?
    /// Read per call so dictionary edits apply to the next dictation.
    private let vocabularyProvider: () -> VocabularyBook

    public init(
        asrManager: AsrManager,
        booster: ParakeetVocabularyBooster? = nil,
        vocabularyProvider: @escaping () -> VocabularyBook = { .init() }
    ) {
        self.asrManager = asrManager
        self.booster = booster
        self.vocabularyProvider = vocabularyProvider
    }

    public func transcribe(samples: [Float], language: Language) async throws -> String {
        let decoderLayers = await asrManager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayers)
        let result = try await asrManager.transcribe(
            samples,
            decoderState: &decoderState,
            // `.init` is resolved from the parameter's own type on purpose.
            // FluidAudio exports an empty `struct FluidAudio` that shadows its own
            // module (their source calls it a namespace collision), so its
            // `Language` enum cannot be spelled out here.
            language: Self.scriptHintCode(for: language).flatMap { .init(rawValue: $0) }
        )
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return await boosted(text, result: result, samples: samples) ?? text
    }

    /// Runs the dictionary against the audio itself, before any text-level layer
    /// sees the transcript. Returns nil whenever boosting does not apply, which
    /// includes every path where the CTC model is missing or fails.
    private func boosted(_ text: String, result: ASRResult, samples: [Float]) async -> String? {
        guard let booster, let timings = result.tokenTimings else { return nil }
        let book = vocabularyProvider()
        guard !book.isEmpty else { return nil }
        return await booster.boost(
            text: text, tokenTimings: timings, samples: samples, book: book
        )
    }

    /// The ISO 639-1 code Drift asks FluidAudio to hold the transcript to, or nil
    /// to leave the decoder unconstrained.
    ///
    /// Both sides use ISO 639-1, so the code passes straight through, and
    /// FluidAudio's initializer returns nil for any language it does not model
    /// (every Indic language, among others). That fallback is the behaviour we
    /// want rather than a gap: the filter can only enforce a script it has been
    /// told, and forcing output into a script the user did not ask for would
    /// corrupt the transcript instead of protecting it. Those languages belong on
    /// the WhisperKit backend, which is why this one does not offer them.
    ///
    /// Auto-detect returns nil for the same reason: there is no declared language
    /// to hold the decoder to.
    static func scriptHintCode(for language: Language) -> String? {
        language.isAuto ? nil : language.code
    }
}
