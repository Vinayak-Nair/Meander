import Foundation

/// Turns recorded audio samples into text. Abstracts the STT engine so the rest
/// of Meander never depends on WhisperKit directly (swappable, testable).
public protocol Transcriber: AnyObject {
    /// Transcribe 16 kHz mono Float samples in the given language.
    func transcribe(samples: [Float], language: Language) async throws -> String
}

/// A transcriber that can emit a partial transcript live while audio is still
/// arriving. Streaming engines (e.g. Nemotron) conform; batch engines don't.
///
/// Lifecycle: `beginStream` → `feed` (repeatedly, as audio arrives) →
/// `finishStream` (returns the final transcript). Implementations process fed
/// audio in order and invoke `onPartial` as new text decodes.
public protocol StreamingTranscriber: Transcriber {
    /// Start a fresh streaming session. `onPartial` is called with the growing
    /// transcript as chunks decode (may be called on a background thread).
    func beginStream(onPartial: @escaping @Sendable (String) -> Void) async

    /// Append 16 kHz mono Float samples. Thread-safe; returns immediately.
    func feed(_ samples: [Float])

    /// End the stream, flush remaining audio, and return the final transcript.
    func finishStream() async throws -> String
}
