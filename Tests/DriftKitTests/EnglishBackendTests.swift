import FluidAudio
import XCTest

@testable import DriftKit

/// Regression tests for the July 2026 wrong-script bug: Parakeet v3 is
/// multilingual and infers its own output language, so short English phrases
/// occasionally came back transliterated into Cyrillic ("Same for Gamma" ->
/// "Сеймфор Гамма").
///
/// The fix is the language hint Drift passes on every transcription, which drives
/// FluidAudio's per-token script filter in the v3 decoder. These tests guard the
/// two halves that have to agree for that to work: the pinned model version, and
/// the hint actually being derived for the selected language.
final class EnglishBackendTests: XCTestCase {

    /// The script filter needs the top-K outputs only the v3 joint model exposes.
    /// On any other version `AsrManager` logs the hint and ignores it, so pinning
    /// away from v3 silently removes the guarantee.
    func testBackendPinsTheVersionThatSupportsScriptFiltering() {
        XCTAssertEqual(ModelManager.parakeetVersion, .v3)
        // Version and repo are declared separately because FluidAudio keeps its
        // mapping internal, so pin both: a pair that disagrees would download one
        // build and try to load another.
        XCTAssertEqual(ModelManager.parakeetRepo, .parakeetV3)
        XCTAssertEqual(ModelManager.parakeetFolderName, "parakeet-tdt-0.6b-v3")
    }

    /// English must produce a hint. Without one the decoder is free to emit any
    /// script it likes, which is exactly how the bug happened.
    func testEnglishProducesAScriptHint() {
        XCTAssertEqual(FluidAudioTranscriber.scriptHintCode(for: .english), "en")
    }

    /// Auto-detect must not be constrained: there is no declared language to hold
    /// the decoder to, and guessing one would corrupt the transcript.
    func testAutoDetectProducesNoHint() {
        XCTAssertNil(FluidAudioTranscriber.scriptHintCode(for: .auto))
    }

    /// The hint is an ISO 639-1 code passed straight through, so every language
    /// Drift could route here has to be expressed in the codes FluidAudio parses.
    /// FluidAudio returns nil for codes it does not model, which is how
    /// unsupported languages end up unconstrained rather than mis-constrained.
    func testHintUsesISO639Codes() {
        // Fully qualified: this file imports FluidAudio too, which has its own
        // `Language` with overlapping case names.
        let cases: [(DriftKit.Language, String)] = [
            (.spanish, "es"), (.french, "fr"), (.german, "de"),
            (.polish, "pl"), (.russian, "ru"), (.greek, "el"),
        ]
        for (language, code) in cases {
            XCTAssertEqual(FluidAudioTranscriber.scriptHintCode(for: language), code)
        }
    }

    /// The real protection for languages FluidAudio cannot model is that they
    /// never reach this backend: it offers no language picker, so Settings pins
    /// English regardless of what the user previously selected.
    func testIndicLanguagesCannotReachTheParakeetBackend() {
        XCTAssertFalse(TranscriptionBackend.fluidAudioParakeet.supportsLanguageSelection)
        for language in [Language.hindi, .malayalam, .tamil, .bengali, .kannada] {
            let settings = Settings(defaults: Self.emptyDefaults())
            settings.transcriptionBackend = .fluidAudioParakeet
            settings.language = language

            XCTAssertEqual(settings.effectiveLanguage, .english)
        }
    }

    /// A backend may only hide the language picker if the language it produces is
    /// guaranteed. `effectiveLanguage` is what reaches the transcriber, so it has
    /// to be a real answer, not a placeholder.
    func testBackendsWithoutLanguageSelectionPinEnglish() {
        for backend in TranscriptionBackend.allCases where !backend.supportsLanguageSelection {
            let settings = Settings(defaults: Self.emptyDefaults())
            settings.transcriptionBackendID = backend.id
            settings.languageCode = Language.russian.code

            XCTAssertEqual(
                settings.effectiveLanguage, .english,
                "\(backend.id) hides the language picker, so it must pin English"
            )
        }
    }

    /// Settings written before the rename must keep resolving to the same backend.
    func testLegacyBackendIDStillResolves() {
        XCTAssertEqual(TranscriptionBackend.from(id: "fluidAudioEnglish"), .fluidAudioParakeet)
        XCTAssertEqual(TranscriptionBackend.from(id: "fluidAudioParakeet"), .fluidAudioParakeet)
    }

    /// WhisperKit is the multilingual escape hatch. If it ever stopped offering a
    /// language picker, users would have no way to dictate anything but English.
    func testWhisperKitStillOffersLanguageSelection() {
        XCTAssertTrue(TranscriptionBackend.whisperKit.supportsLanguageSelection)
        XCTAssertTrue(Language.whisperKitLanguages.contains(.auto))
    }

    private static func emptyDefaults() -> UserDefaults {
        let suite = "drift.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
