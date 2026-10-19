import XCTest
@testable import MeanderKit

final class VocabularyCorrectorTests: XCTestCase {
    private let vocab = ["Karan Johar", "Aishwarya Rai", "Bengaluru"]

    func testRestoresPhoneticallyCloseName() {
        XCTAssertEqual(
            VocabularyCorrector.correct("I met current johar yesterday", vocabulary: vocab),
            "I met Karan Johar yesterday"
        )
    }

    func testPreservesSurroundingPunctuation() {
        XCTAssertEqual(
            VocabularyCorrector.correct("Have you met current johar?", vocabulary: vocab),
            "Have you met Karan Johar?"
        )
    }

    func testFixesCasingOfExactMatch() {
        XCTAssertEqual(
            VocabularyCorrector.correct("karan johar is here", vocabulary: vocab),
            "Karan Johar is here"
        )
    }

    func testLeavesCorrectTextUntouched() {
        let text = "Karan Johar is here"
        XCTAssertEqual(VocabularyCorrector.correct(text, vocabulary: vocab), text)
    }

    func testSingleWordRespellings() {
        XCTAssertEqual(
            VocabularyCorrector.correct("I flew to bangalore last week", vocabulary: vocab),
            "I flew to Bengaluru last week"
        )
    }

    func testDoesNotTouchUnrelatedText() {
        let text = "the current year is busy"
        XCTAssertEqual(VocabularyCorrector.correct(text, vocabulary: vocab), text)
    }

    func testEmptyVocabularyIsNoOp() {
        let text = "current johar was there"
        XCTAssertEqual(VocabularyCorrector.correct(text, vocabulary: []), text)
    }

    func testPreservesNewlines() {
        XCTAssertEqual(
            VocabularyCorrector.correct("current johar\nhello there", vocabulary: vocab),
            "Karan Johar\nhello there"
        )
    }

    func testSeverelyMangledCaptureIsLeftForLLMLayer() {
        // Documents the deliberate limit: this mangle is too far for a
        // deterministic matcher, so it must not be "fixed" into a false positive.
        let text = "I should have a run"
        XCTAssertEqual(VocabularyCorrector.correct(text, vocabulary: vocab), text)
    }

    func testMultipleTermsInOneUtterance() {
        XCTAssertEqual(
            VocabularyCorrector.correct("current johar met ash warya rai in bangalore", vocabulary: vocab),
            "Karan Johar met Aishwarya Rai in Bengaluru"
        )
    }

    // MARK: Ordinary English is never rewritten on sound alone

    /// The failure that made dictation unusable: a dictionary that had collected
    /// ordinary words rewrote correct transcripts, and every added term made it
    /// worse. Each of these is a real substitution the corrector used to make.
    func testDoesNotRewriteOrdinaryWordsThatSoundLikeTerms() {
        let polluted = ["Connect", "taking", "present", "Parakeet 3", "cant", "term", "mode", "the"]
        let sentences = [
            "I was talking to the president about the connected app.",
            "The Indian market is worth ten percent of the total.",
            "She updated the code and logged in via Mac.",
            "Are they the best team for this evening?",
            "That is a really candid conversation about the coast.",
        ]
        for sentence in sentences {
            XCTAssertEqual(
                VocabularyCorrector.correct(sentence, vocabulary: polluted),
                sentence,
                "rewrote correct text"
            )
        }
    }

    /// A term must not reach past the ordinary-word check by claiming a wider
    /// span: "Connect" cannot have "connected", so it used to take "connected
    /// app" and delete a word in the process.
    func testDoesNotSwallowAdjacentWordsToReachAnOrdinaryWord() {
        let text = "I opened the connected app today"
        XCTAssertEqual(VocabularyCorrector.correct(text, vocabulary: ["Connect"]), text)
    }

    /// Capitals in the transcript survive a term the user happened to type in
    /// lower case, and the locked span can't then be claimed by a wider window.
    func testDoesNotStripCapitalsUsingALowercaseTerm() {
        let text = "Kollam is a city in Kerala"
        XCTAssertEqual(VocabularyCorrector.correct(text, vocabulary: ["kollam"]), text)
    }

    /// Short terms have short phonetic keys, which puts most of the language
    /// within one edit of them, so they match exactly or not at all.
    func testShortTermsDoNotMatchPhonetically() {
        let text = "we shipped the crumb and the card"
        XCTAssertEqual(VocabularyCorrector.correct(text, vocabulary: ["CRM", "CRED"]), text)
    }

    // MARK: Learned mistakes

    private func book(_ term: String, aliases: [String]) -> VocabularyBook {
        VocabularyBook(
            terms: [term],
            metadata: [VocabularyEntry(term: term, aliases: aliases, sources: [])]
        )
    }

    /// The payoff for recording mistakes: a mangle the phonetic matcher refuses
    /// to touch (see `testSeverelyMangledCaptureIsLeftForLLMLayer`) is repaired
    /// exactly once the user has demonstrated it once.
    func testLearnedMistakeFixesWhatPhoneticsCannotReach() {
        let b = book("Aishwarya Rai", aliases: ["i should have a run"])
        XCTAssertEqual(
            VocabularyCorrector.correct("I should have a run is my favorite actress", book: b),
            "Aishwarya Rai is my favorite actress"
        )
    }

    func testLearnedMistakeMatchesRegardlessOfCasingAndPunctuation() {
        let b = book("Karan Johar", aliases: ["current johar"])
        XCTAssertEqual(
            VocabularyCorrector.correct("Call Current Johar, please", book: b),
            "Call Karan Johar, please"
        )
    }

    /// A correctly spelled term must never be clobbered by an alias that happens
    /// to overlap its span.
    func testCorrectlySpelledTermSurvivesAliasPass() {
        let b = book("Karan Johar", aliases: ["johar"])
        XCTAssertEqual(
            VocabularyCorrector.correct("Karan Johar is here", book: b),
            "Karan Johar is here"
        )
    }

    func testTextWithoutAnyMatchIsUntouched() {
        let b = book("Karan Johar", aliases: ["current johar"])
        let text = "the meeting is at noon"
        XCTAssertEqual(VocabularyCorrector.correct(text, book: b), text)
    }

    /// A learned alias must not make nearby ordinary speech expand into the
    /// dictionary term. This mirrors the user's real dictionary, where
    /// "what is dlc" was learned for "Ask ChatGPT" but "what I'm trying"
    /// is unrelated prose and must remain untouched.
    func testLearnedAliasDoesNotRewriteNearbyOrdinarySpeech() {
        let b = book("Ask ChatGPT", aliases: ["what is dlc"])
        let text = "No no, what I'm trying to say is that change from Parakeet to Whisper."
        XCTAssertEqual(VocabularyCorrector.correct(text, book: b), text)
    }

    func testParakeetAliasGateRejectsDistantCollisionAndKeepsCloseCorrection() {
        let b = book("Ask ChatGPT", aliases: ["what is dlc", "ask gp"])
            .retainingAliases(
                minimumSpellingSimilarity: ParakeetVocabularyBooster.minimumLearnedAliasSimilarity
            )
        XCTAssertEqual(
            VocabularyCorrector.correct("No no, what is DLC trying to say.", book: b),
            "No no, what is DLC trying to say."
        )
        XCTAssertEqual(
            VocabularyCorrector.correct("Ask GP to summarize it.", book: b),
            "Ask ChatGPT to summarize it."
        )
    }

    /// An empty book must behave exactly like an empty vocabulary list.
    func testEmptyBookLeavesTextAlone() {
        let text = "current johar"
        XCTAssertEqual(VocabularyCorrector.correct(text, book: VocabularyBook()), text)
    }
}
