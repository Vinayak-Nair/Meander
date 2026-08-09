import XCTest

@testable import MeanderKit

/// Regression tests for the August 2026 `<unk>` paste: two dictated words came
/// back from Parakeet as its unknown-token literal and landed in the user's
/// document as "<Unk> <unk>..". FluidAudio joins vocabulary strings verbatim, so
/// control tokens are ordinary text by the time Meander sees them.
final class TranscriptSanitizerTests: XCTestCase {

    /// The exact shape that was pasted: nothing decoded, so nothing should be
    /// pasted. The trailing dots the model emitted around the unknown tokens are
    /// not a transcript.
    func testTranscriptOfOnlyControlTokensBecomesEmpty() {
        XCTAssertEqual(TranscriptSanitizer.sanitize("<unk> <unk> . ."), "")
        XCTAssertEqual(TranscriptSanitizer.sanitize("<unk>"), "")
        XCTAssertEqual(TranscriptSanitizer.sanitize("<|nospeech|>"), "")
    }

    /// A single unknown word must not cost the rest of the sentence.
    func testControlTokensAreRemovedFromOtherwiseGoodText() {
        XCTAssertEqual(
            TranscriptSanitizer.sanitize("Restart the <unk> and try again."),
            "Restart the and try again."
        )
        XCTAssertEqual(
            TranscriptSanitizer.sanitize("<|startoftranscript|><|en|>Ship it."),
            "Ship it."
        )
        XCTAssertEqual(TranscriptSanitizer.sanitize("<pad>Hello<pad>"), "Hello")
    }

    /// SentencePiece attaches an unknown token to the word before it, so removing
    /// it has to leave that word whole rather than split in two.
    func testUnknownTokenAttachedToAWordLeavesTheWordIntact() {
        XCTAssertEqual(TranscriptSanitizer.sanitize("router<unk>"), "router")
    }

    /// Only the two vocabulary shapes count. Dictated angle brackets are speech.
    func testOrdinaryAngleBracketsSurvive() {
        XCTAssertEqual(TranscriptSanitizer.sanitize("if a < b and c > d"), "if a < b and c > d")
        XCTAssertEqual(TranscriptSanitizer.sanitize("<div>"), "<div>")
        XCTAssertFalse(TranscriptSanitizer.containsControlTokens("a <b> c"))
        XCTAssertTrue(TranscriptSanitizer.containsControlTokens("a <unk> c"))
    }

    /// The punctuation-only rule judges only what it stripped: a transcript that
    /// never contained a control token is passed through untouched, so command
    /// mode's punctuation output is unaffected.
    func testCleanTranscriptIsOnlyTrimmed() {
        XCTAssertEqual(TranscriptSanitizer.sanitize("  Hello there.  "), "Hello there.")
        XCTAssertEqual(TranscriptSanitizer.sanitize("?"), "?")
        XCTAssertEqual(TranscriptSanitizer.sanitize("नमस्ते"), "नमस्ते")
    }

    /// Non-Latin scripts have letters too: stripping a control token out of Hindi
    /// must not empty the transcript.
    func testNonLatinTextSurvivesStripping() {
        XCTAssertEqual(TranscriptSanitizer.sanitize("<unk> नमस्ते"), "नमस्ते")
    }
}
