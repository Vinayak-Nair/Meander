import AVFoundation
import Foundation
import FluidAudio

/// Nemotron 3.5 ASR Streaming Multilingual 0.6B through FluidAudio. Unlike the
/// English Nemotron prototype it takes a language hint (or "auto"), so it can back
/// a language picker. Meander's `Transcriber` is batch-shaped, so the whole
/// utterance goes through the streaming pipeline at once, padded with silence so
/// the encoder's right-context latency does not clip the last words.
public final class NemotronMultilingualTranscriber: Transcriber {
    private let manager: StreamingNemotronMultilingualAsrManager
    private static let leadSilence = 4_800   // 300 ms
    private static let tailSilence = 24_000  // 1.5 s

    public init(manager: StreamingNemotronMultilingualAsrManager) {
        self.manager = manager
    }

    public func transcribe(samples: [Float], language: Language) async throws -> String {
        guard !samples.isEmpty else { return "" }
        await manager.reset()
        await manager.setLanguage(language == .auto ? "auto" : language.code)

        let padded = [Float](repeating: 0, count: Self.leadSilence)
            + samples + [Float](repeating: 0, count: Self.tailSilence)
        _ = try await manager.process(samples: padded)
        let text = try await manager.finish()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
