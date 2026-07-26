import XCTest
@testable import DriftKit

final class CleanupFactoryTests: XCTestCase {
    private func makeSettings() -> Settings {
        let suite = "drift-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Settings(defaults: defaults)
    }

    func testDefaultsToDeterministicCleanup() {
        // On-device rules are the instant, always-available default now that the
        // Apple Intelligence LLM path (14-21s cold-load per dictation) is gone.
        XCTAssertEqual(makeSettings().cleanupProviderID, "deterministic")
        XCTAssertEqual(CleanupFactory.make(settings: makeSettings()).id, "deterministic")
    }

    func testSelectsProviderByID() {
        for id in ["none", "openai", "ollama", "deterministic"] {
            let s = makeSettings()
            s.cleanupProviderID = id
            XCTAssertEqual(CleanupFactory.make(settings: s).id, id)
        }
    }

    func testLegacyAppleSettingMapsToDeterministic() {
        // Users who had Apple Intelligence selected fall back cleanly instead of
        // hitting an unknown provider id.
        let s = makeSettings()
        s.cleanupProviderID = "apple"
        XCTAssertEqual(s.cleanupProviderID, "deterministic")
        XCTAssertEqual(CleanupFactory.make(settings: s).id, "deterministic")
    }

    func testRegistryDoesNotListApple() {
        XCTAssertFalse(CleanupRegistry.all.contains { $0.id == "apple" })
        // The universal floor must always be present.
        XCTAssertTrue(CleanupRegistry.all.contains { $0.id == "deterministic" })
    }

    func testProviderNetworkFlags() {
        let s = makeSettings()
        s.cleanupProviderID = "openai"
        XCTAssertTrue(CleanupFactory.make(settings: s).requiresNetwork)
        s.cleanupProviderID = "deterministic"
        XCTAssertFalse(CleanupFactory.make(settings: s).requiresNetwork)
    }

    func testLanguageRoundTrip() {
        let s = makeSettings()
        s.language = .malayalam
        XCTAssertEqual(s.language, .malayalam)
        XCTAssertEqual(s.languageCode, "ml")
    }

    func testDefaultsToFluidAudioEnglishBackend() {
        XCTAssertEqual(makeSettings().transcriptionBackend, .fluidAudioEnglish)
    }

    func testFluidAudioBackendForcesEffectiveLanguageToEnglish() {
        let s = makeSettings()
        s.language = .malayalam
        s.transcriptionBackend = .fluidAudioEnglish
        XCTAssertEqual(s.effectiveLanguage, .english)
    }

    func testWhisperKitBackendUsesSelectedLanguage() {
        let s = makeSettings()
        s.language = .malayalam
        s.transcriptionBackend = .whisperKit
        XCTAssertEqual(s.effectiveLanguage, .malayalam)
    }

    func testWhisperKitBackendUsesInternationalLanguage() {
        let s = makeSettings()
        s.language = .japanese
        s.transcriptionBackend = .whisperKit
        XCTAssertEqual(s.effectiveLanguage, .japanese)
    }

    func testWhisperKitBackendHonorsAutoDetect() {
        let s = makeSettings()
        s.language = .auto
        s.transcriptionBackend = .whisperKit
        XCTAssertEqual(s.effectiveLanguage, .auto)
    }

    func testWhisperKitLanguagesCoverIndicAndInternational() {
        XCTAssertTrue(Language.whisperKitLanguages.contains(.hindi))
        XCTAssertTrue(Language.whisperKitLanguages.contains(.tamil))
        XCTAssertTrue(Language.whisperKitLanguages.contains(.malayalam))
        XCTAssertTrue(Language.whisperKitLanguages.contains(.kannada))
        XCTAssertTrue(Language.whisperKitLanguages.contains(.telugu))
        XCTAssertTrue(Language.whisperKitLanguages.contains(.spanish))
        XCTAssertTrue(Language.whisperKitLanguages.contains(.chinese))
        XCTAssertTrue(Language.whisperKitLanguages.contains(.arabic))
    }

    func testDefaultModelIsTurbo() {
        XCTAssertEqual(makeSettings().modelVariant, "openai_whisper-large-v3-v20240930")
    }
}
