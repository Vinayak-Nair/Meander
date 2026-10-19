import FluidAudio
import XCTest

@testable import MeanderKit

/// Guards the cheap half of the Parakeet dictionary booster: the conditions under
/// which it must decline before touching a model.
///
/// This matters more than it looks. The booster's model is a second download the
/// user did not ask for, and its failure mode sits directly in the dictation
/// path. Every case here is one where it must cost nothing: no download, no load,
/// and a transcript that comes back exactly as Parakeet produced it. Pointing the
/// booster at a directory with no model is what proves it — any code path that
/// reached the model would throw or hang instead of returning nil.
final class ParakeetVocabularyBoosterTests: XCTestCase {
    func testDisablesAcousticOnlySpotterRescue() {
        XCTAssertFalse(ParakeetVocabularyBooster.rescorerConfig.spotterRescueEnabled)
    }

    func testRejectsWeakSmallVocabularyMatches() {
        XCTAssertEqual(
            ParakeetVocabularyBooster.replacementSimilarity(forVocabularySize: 2),
            0.60
        )
    }

    func testRequiresDictionaryTermToWinAcousticallyWithoutFreeBoost() {
        XCTAssertEqual(ParakeetVocabularyBooster.contextBiasingWeight, 0)
    }

    func testKeepsOnlyAliasesCloseToCanonicalTerm() {
        let entry = VocabularyEntry(
            term: "Ask ChatGPT",
            aliases: ["what is dlc", "ask gp", "ask judge gpt"],
            sources: []
        )
        XCTAssertEqual(
            ParakeetVocabularyBooster.safeAliases(for: entry),
            ["ask gp", "ask judge gpt"]
        )
    }

    func testDoesNotLoosenFluidAudioThresholdForLargeVocabulary() {
        let fluidAudioThreshold = ContextBiasingConstants
            .rescorerConfig(forVocabSize: 101)
            .minSimilarity
        XCTAssertGreaterThanOrEqual(
            ParakeetVocabularyBooster.replacementSimilarity(forVocabularySize: 101),
            fluidAudioThreshold
        )
    }

    private func makeBooster() -> ParakeetVocabularyBooster {
        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meander-test-no-ctc-\(UUID().uuidString)", isDirectory: true)
        return ParakeetVocabularyBooster(modelDirectory: empty)
    }

    private var book: VocabularyBook {
        VocabularyBook(
            terms: ["Karan Johar"],
            metadata: [VocabularyEntry(term: "Karan Johar", aliases: ["current johar"], sources: [])]
        )
    }

    private func timings() -> [TokenTiming] {
        [TokenTiming(token: "current", tokenId: 1, startTime: 0, endTime: 0.5, confidence: 1)]
    }

    func testDeclinesWhenDictionaryIsEmpty() async {
        let result = await makeBooster().boost(
            text: "current johar",
            tokenTimings: timings(),
            samples: [Float](repeating: 0, count: 16_000),
            book: VocabularyBook()
        )
        XCTAssertNil(result)
    }

    /// Rescoring is anchored on where each word sits in the audio; with no
    /// timings there is nothing to anchor and the term could land anywhere.
    func testDeclinesWithoutTokenTimings() async {
        let result = await makeBooster().boost(
            text: "current johar",
            tokenTimings: [],
            samples: [Float](repeating: 0, count: 16_000),
            book: book
        )
        XCTAssertNil(result)
    }

    func testDeclinesWithoutAudio() async {
        let result = await makeBooster().boost(
            text: "current johar",
            tokenTimings: timings(),
            samples: [],
            book: book
        )
        XCTAssertNil(result)
    }

    func testDeclinesOnEmptyTranscript() async {
        let result = await makeBooster().boost(
            text: "",
            tokenTimings: timings(),
            samples: [Float](repeating: 0, count: 16_000),
            book: book
        )
        XCTAssertNil(result)
    }

    /// The case that actually reaches users: dictionary present, model not
    /// installed. It has to degrade to "no boost" without reaching the network,
    /// because this runs between the user releasing the hotkey and the paste.
    func testUninstalledModelDeclinesWithoutDownloading() async {
        let booster = makeBooster()
        let installed = await booster.isModelInstalled
        XCTAssertFalse(installed)

        let result = await booster.boost(
            text: "current johar",
            tokenTimings: timings(),
            samples: [Float](repeating: 0, count: 16_000),
            book: book
        )
        XCTAssertNil(result)
    }
}
