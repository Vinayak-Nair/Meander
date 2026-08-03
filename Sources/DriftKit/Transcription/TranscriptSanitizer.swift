import Foundation

/// Removes the engine's own control tokens from a transcript.
///
/// Parakeet's vocabulary holds `<unk>`, `<pad>` and 262 `<|…|>` control tokens
/// (per-language tags, `<|nospeech|>`, `<|endoftext|>`), and FluidAudio decodes
/// by joining vocabulary strings verbatim: nothing filters them out. A word the
/// model cannot decode therefore arrives as the literal text `<unk>` and, with
/// no layer downstream treating it as anything but a word, gets pasted. Whisper
/// spells its control tokens the same `<|…|>` way, so one rule covers both
/// engines.
///
/// This is the only place that knows those strings are not speech. It runs on
/// raw transcriber output, before cleanup and before the dictionary, so no later
/// layer has to reason about them.
public enum TranscriptSanitizer {
    /// The two shapes the vocabularies use. Deliberately narrow: only these exact
    /// forms are control tokens, so dictated angle brackets (`a < b`, or markup
    /// spoken into a code destination) are left alone.
    private static let pattern = "<\\|[^|>]*\\|>|<unk>|<pad>"

    /// Whether `text` contains any control token. Callers use this to log a
    /// decode that went wrong; `sanitize` does the removal.
    public static func containsControlTokens(_ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Returns `text` with control tokens removed, or "" when removing them
    /// leaves nothing but punctuation.
    ///
    /// The empty result is the point. An utterance that decoded to control tokens
    /// has no words in it, and the punctuation the model emits around them
    /// (`<unk> <unk> . .` → `. .`) is not a transcript. "" routes it to the
    /// pipeline's existing empty path, where Drift pastes nothing and plays the
    /// empty sound, so the user retries instead of deleting stray dots.
    ///
    /// Text without control tokens is returned trimmed and otherwise untouched,
    /// punctuation-only transcripts included: this only judges what it stripped.
    public static func sanitize(_ text: String) -> String {
        guard containsControlTokens(text) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Dropped rather than replaced with a space: SentencePiece attaches an
        // unknown token to the word before it ("router<unk>"), so removing it
        // leaves the word whole instead of splitting it.
        var stripped = text.replacingOccurrences(
            of: pattern, with: "", options: [.regularExpression, .caseInsensitive]
        )
        stripped = stripped.replacingOccurrences(
            of: "[ \\t]{2,}", with: " ", options: .regularExpression
        )
        stripped = stripped.trimmingCharacters(in: .whitespacesAndNewlines)

        guard stripped.contains(where: { $0.isLetter || $0.isNumber }) else { return "" }
        return stripped
    }
}
