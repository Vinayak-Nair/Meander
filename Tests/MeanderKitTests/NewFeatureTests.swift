import XCTest

@testable import MeanderKit

private func freshSettings() -> Settings {
    let suite = "meander.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return Settings(defaults: defaults)
}

/// The engine list grew a lot; these guard the invariants the app relies on.
final class TranscriptionBackendCatalogTests: XCTestCase {
    func testBackendIDsAreUniqueAndRoundTrip() {
        let ids = TranscriptionBackend.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for backend in TranscriptionBackend.allCases {
            XCTAssertEqual(TranscriptionBackend.from(id: backend.id), backend)
        }
    }

    func testUnknownBackendIDFallsBackToTheDefault() {
        XCTAssertEqual(TranscriptionBackend.from(id: "does-not-exist"), .fluidAudioParakeet)
        XCTAssertEqual(TranscriptionBackend.defaultBackend, .fluidAudioParakeet)
    }

    func testOnlyWhisperAndNemotronMultilingualOfferALanguagePicker() {
        let withPicker = TranscriptionBackend.allCases.filter(\.supportsLanguageSelection)
        XCTAssertEqual(Set(withPicker), [.whisperKit, .nemotronMultilingual])
    }

    func testMultilingualBackendsHonourTheUsersLanguage() {
        for backend in [TranscriptionBackend.whisperKit, .nemotronMultilingual] {
            let settings = freshSettings()
            settings.transcriptionBackendID = backend.id
            settings.languageCode = Language.german.code
            XCTAssertEqual(settings.effectiveLanguage, .german)
        }
    }

    func testEveryBackendHasADisplayName() {
        for backend in TranscriptionBackend.allCases {
            XCTAssertFalse(backend.displayName.isEmpty)
        }
    }

    func testAppleSpeechAvailabilityMatchesTheOS() {
        let expected: Bool
        if #available(macOS 26.0, *) { expected = true } else { expected = false }
        XCTAssertEqual(TranscriptionBackend.appleSpeech.isAvailableOnThisSystem, expected)
        for backend in TranscriptionBackend.allCases where backend != .appleSpeech {
            XCTAssertTrue(backend.isAvailableOnThisSystem)
        }
    }
}

final class NewSettingsDefaultsTests: XCTestCase {
    func testNewFeaturesAreOffByDefault() {
        let settings = freshSettings()
        XCTAssertFalse(settings.pressToToggle)
        XCTAssertFalse(settings.quillEnabled)
        XCTAssertFalse(settings.autocompleteEnabled)
    }

    func testQuillKeyDefaultsToRightControl() {
        XCTAssertEqual(freshSettings().quillKeyCode, 62)
    }

    func testAutocompleteAllowlistNeverIncludesTerminalsOrPasswordManagers() {
        let apps = freshSettings().autocompleteApps
        XCTAssertFalse(apps.isEmpty)
        for blocked in ["com.apple.Terminal", "com.googlecode.iterm2", "com.apple.dt.Xcode"] {
            XCTAssertFalse(apps.contains(blocked))
        }
    }

    func testSettingsRoundTrip() {
        let settings = freshSettings()
        settings.pressToToggle = true
        settings.quillEnabled = true
        settings.autocompleteEnabled = true
        settings.autocompleteApps = ["com.apple.Notes"]
        XCTAssertTrue(settings.pressToToggle)
        XCTAssertTrue(settings.quillEnabled)
        XCTAssertTrue(settings.autocompleteEnabled)
        XCTAssertEqual(settings.autocompleteApps, ["com.apple.Notes"])
    }
}

final class CompletionSanitizeTests: XCTestCase {
    func testKeepsOnlyTheFirstLine() {
        let out = CompletionPrompt.sanitize(" and then we left\nSecond line", prefix: "We arrived early")
        XCTAssertEqual(out, " and then we left")
    }

    func testDropsAnEchoedPrefixTail() {
        let out = CompletionPrompt.sanitize("see you tomorrow morning", prefix: "ok, see you ")
        XCTAssertEqual(out, "tomorrow morning")
    }

    func testKeepsAContinuationThatMerelySharesALetter() {
        let out = CompletionPrompt.sanitize(" and then", prefix: "We arrived")
        XCTAssertEqual(out, " and then")
    }

    func testEmptyOrWhitespaceBecomesEmpty() {
        XCTAssertEqual(CompletionPrompt.sanitize("   ", prefix: "Hello there"), "")
        XCTAssertEqual(CompletionPrompt.sanitize("\n", prefix: "Hello there"), "")
    }

    func testNoLeadingSpaceWhenThePrefixAlreadyEndsInOne() {
        let out = CompletionPrompt.sanitize("  for the update", prefix: "Thanks ")
        XCTAssertEqual(out, "for the update")
    }

    func testIsCappedInLength() {
        let long = String(repeating: "word ", count: 200)
        XCTAssertLessThanOrEqual(CompletionPrompt.sanitize(long, prefix: "Start ").count, 120)
    }
}

final class QuillPromptTests: XCTestCase {
    func testRewritePromptIncludesInstructionAndSelection() {
        let prompt = QuillPrompt.user(selection: "hey bob", instruction: "make it formal")
        XCTAssertTrue(prompt.contains("make it formal"))
        XCTAssertTrue(prompt.contains("hey bob"))
    }

    func testGenerationPromptHasNoTextSection() {
        let prompt = QuillPrompt.user(selection: "", instruction: "write a two line thank you")
        XCTAssertTrue(prompt.contains("write a two line thank you"))
        XCTAssertFalse(prompt.contains("Text:"))
    }

    func testSystemPromptDemandsBareOutput() {
        XCTAssertTrue(QuillPrompt.system.contains("ONLY"))
    }

    func testOnlyLLMProvidersCanRewrite() {
        XCTAssertTrue(OllamaCleanup(baseURL: "http://localhost", model: "m") is RewriteProvider)
        XCTAssertTrue(OpenAICompatibleCleanup(baseURL: "http://x", model: "m", apiKey: "") is RewriteProvider)
        XCTAssertFalse(DeterministicCleanup() is RewriteProvider)
        XCTAssertFalse(PassthroughCleanup() is RewriteProvider)
    }
}
