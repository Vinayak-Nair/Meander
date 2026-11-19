import Foundation
import FluidAudio

/// Parakeet Unified 0.6B (English) through FluidAudio's *offline* manager: the
/// full-attention encoder over 15 s windows, which gives the model's best WER.
/// Meander records whole push-to-talk utterances, so batch-on-finish costs nothing
/// and beats the chunked streaming tiers on accuracy.
public final class ParakeetUnifiedTranscriber: Transcriber {
    private let manager: UnifiedAsrManager

    public init(manager: UnifiedAsrManager) {
        self.manager = manager
    }

    public func transcribe(samples: [Float], language _: Language) async throws -> String {
        guard !samples.isEmpty else { return "" }
        let text = try await manager.transcribe(samples)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
