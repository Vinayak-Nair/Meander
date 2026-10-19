@testable import MeanderKit
import XCTest

/// The sound-alike rescorer asks the recording, and only the recording, whether
/// Parakeet picked the right one of several near-identical spellings.
///
/// These tests drive it with hand-written log-probabilities so every decision has
/// a known right answer. The mechanism is exercised through a stand-in group
/// ("cat"/"cot") because the shipping table is empty - see
/// `testShippingTableIsEmptyBecauseTheMeasurementDidNotSupportLogLock`.
final class SoundAlikeRescorerTests: XCTestCase {
    // Vocabulary: 0 = shared first token, 1 = "cat" ending, 2 = "cot" ending, 3 = blank.
    private let blank = 3
    private let groups = [["cat", "cot"]]

    private func tokens(_ word: String) -> [[Int]] {
        switch word {
        case "cat", "cats", "catted", "catting", "cat's": return [[0, 1]]
        case "cot", "cots", "cotted", "cotting", "cot's": return [[0, 2]]
        default: return [[0, 0]]
        }
    }

    private func frame(certain symbol: Int) -> [Float] {
        (0..<4).map { $0 == symbol ? -0.01 : -6.0 }
    }

    /// Frames spanning one word, saying `symbol` after the shared opening token.
    private func audio(saying symbol: Int) -> [[Float]] {
        [frame(certain: blank), frame(certain: 0), frame(certain: symbol), frame(certain: blank)]
    }

    private func rescorer(minimumWinMargin: Double) -> SoundAlikeRescorer {
        SoundAlikeRescorer(
            config: .init(marginSeconds: 0, minimumWinMargin: minimumWinMargin),
            groups: groups,
            tokenize: { [self] in tokens($0) }
        )
    }

    private func rescore(
        _ text: String,
        words: [TimedWord],
        saying symbol: Int,
        minimumWinMargin: Double = 1.0
    ) -> SoundAlikeRescorer.Result {
        rescorer(minimumWinMargin: minimumWinMargin).rescore(
            text: text, words: words, logProbs: audio(saying: symbol), frameDuration: 1, blankId: blank
        )
    }

    private func oneWord(_ word: String) -> [TimedWord] {
        [TimedWord(text: word, startTime: 0, endTime: 4)]
    }

    // MARK: The decision rule

    /// When the audio plainly says the other word, the rival wins and the
    /// transcript is corrected.
    func testReplacesWhenTheAudioClearlySupportsTheRival() {
        let result = rescore("cat", words: oneWord("cat"), saying: 2)
        XCTAssertEqual(result.text, "cot")
        XCTAssertEqual(result.verdicts.first?.replacement, "cot")
    }

    /// Parakeet's own word stands unless it is beaten by the full margin. This is
    /// the guarantee that makes the layer safe to add at all.
    func testKeepsParakeetsWordWhenTheAudioAgreesWithIt() {
        let result = rescore("cat", words: oneWord("cat"), saying: 1)
        XCTAssertEqual(result.text, "cat")
        XCTAssertNil(result.verdicts.first?.replacement)
        XCTAssertFalse(result.wasModified)
    }

    /// A rival that wins, but only narrowly, is not enough. The margin is the
    /// difference between a measurement and a coin flip.
    func testKeepsParakeetsWordWhenTheRivalWinsByLessThanTheMargin() {
        let narrow = SoundAlikeRescorer(
            config: .init(marginSeconds: 0, minimumWinMargin: 50),
            groups: groups,
            tokenize: { [self] in tokens($0) }
        )
        let result = narrow.rescore(
            text: "cat", words: oneWord("cat"), logProbs: audio(saying: 2), frameDuration: 1, blankId: blank
        )
        XCTAssertEqual(result.text, "cat")
        XCTAssertNil(result.verdicts.first?.replacement)
        // The rival did win on the audio; the margin is what held the word.
        XCTAssertEqual(result.verdicts.first?.candidates.first?.word, "cot")
        XCTAssertGreaterThan(result.verdicts.first?.margin ?? 0, 0)
    }

    /// Every group spelling is reported with its score, so a decision can always
    /// be explained by the numbers behind it.
    func testReportsEveryCandidateScoreBestFirst() {
        let verdict = rescore("cat", words: oneWord("cat"), saying: 2).verdicts.first
        XCTAssertEqual(verdict?.original, "cat")
        XCTAssertEqual(verdict?.candidates.map(\.word), ["cot", "cat"])
        XCTAssertEqual(verdict?.candidates.count, 2)
    }

    // MARK: Word shapes

    /// Endings ride along with the pair: nothing writes down "cats" or "cotting",
    /// they follow from ordinary English spelling rules.
    func testCarriesRegularEndingsWithoutListingThem() {
        for (original, expected) in [
            ("cats", "cots"), ("catted", "cotted"), ("catting", "cotting"), ("cat's", "cot's"),
        ] {
            let result = rescore(original, words: oneWord(original), saying: 2)
            XCTAssertEqual(result.text, expected, "\(original) should become \(expected)")
        }
    }

    /// The consonant-doubling rule is spelling, not vocabulary: "log" doubles
    /// before a vowel-initial ending, "lock" does not.
    func testAppliesEnglishDoublingAndSibilantRules() {
        XCTAssertEqual(WordSuffix.past.applied(to: "log"), "logged")
        XCTAssertEqual(WordSuffix.past.applied(to: "lock"), "locked")
        XCTAssertEqual(WordSuffix.progressive.applied(to: "log"), "logging")
        XCTAssertEqual(WordSuffix.progressive.applied(to: "lock"), "locking")
        XCTAssertEqual(WordSuffix.plural.applied(to: "log"), "logs")
        XCTAssertEqual(WordSuffix.plural.applied(to: "watch"), "watches")
        XCTAssertEqual(WordSuffix.possessive.applied(to: "log"), "log's")
    }

    /// Punctuation and capitalization belong to the sentence, not to the word
    /// being judged, and must survive a replacement untouched.
    func testPreservesSurroundingPunctuationAndCapitalization() {
        XCTAssertEqual(rescore("\"Cat.\"", words: oneWord("\"Cat.\""), saying: 2).text, "\"Cot.\"")
        XCTAssertEqual(rescore("CAT!", words: oneWord("CAT!"), saying: 2).text, "COT!")
    }

    /// Words outside the table are never touched, however they sound.
    func testLeavesWordsOutsideTheTableAlone() {
        let result = rescore("dog", words: oneWord("dog"), saying: 2)
        XCTAssertEqual(result.text, "dog")
        XCTAssertTrue(result.verdicts.isEmpty)
    }

    // MARK: Refusing to guess

    /// Without a trustworthy word-to-audio alignment there is no trustworthy
    /// window, so the transcript is left exactly as it was.
    func testLeavesTheTranscriptAloneWhenTimingsDoNotLineUp() {
        let mismatchedCount = rescore("the cat", words: oneWord("cat"), saying: 2)
        XCTAssertEqual(mismatchedCount.text, "the cat")
        XCTAssertTrue(mismatchedCount.verdicts.isEmpty)

        // Right number of words, wrong words: the timing describes something else.
        let mismatchedWord = rescore("cat", words: oneWord("dog"), saying: 2)
        XCTAssertEqual(mismatchedWord.text, "cat")
        XCTAssertTrue(mismatchedWord.verdicts.isEmpty)
    }

    /// Only the word under judgement moves; its neighbours are copied through.
    func testChangesOnlyTheWordItJudged() {
        let words = [
            TimedWord(text: "the", startTime: 0, endTime: 1),
            TimedWord(text: "cat", startTime: 1, endTime: 4),
        ]
        let result = rescore("the cat.", words: words, saying: 2)
        XCTAssertEqual(result.text, "the cot.")
    }

    func testWithoutAudioNothingIsDecided() {
        let empty = rescorer(minimumWinMargin: 1.0).rescore(
            text: "cat", words: oneWord("cat"), logProbs: [], frameDuration: 1, blankId: blank
        )
        XCTAssertEqual(empty.text, "cat")
        XCTAssertTrue(empty.verdicts.isEmpty)
    }

    // MARK: The measured finding

    /// log/lock is **not** in the shipping table, and this test is what keeps it
    /// out until someone has evidence to put it back.
    ///
    /// Measured on 108 synthesized clips (18 sentences x 6 voices; 117 log/lock
    /// occurrences) and then on real speech (one speaker, 20 phrases).
    ///
    /// Synthesized: Parakeet TDT v3 alone was 90.6% correct; the CTC head, asked
    /// which spelling its own audio supported, was right 39-50% of the time across
    /// alignment windows of 0.00s to 0.20s, leaning toward "log" regardless of what
    /// was said. Real speech: Parakeet got 19 of 20; the CTC head got 13 at best,
    /// and backed Parakeet's one error by 1.65 nats rather than repairing it. At
    /// every window the best available threshold was net -1, nothing repaired and
    /// one correct word broken.
    ///
    /// No threshold can rescue this, because CTC's confidence does not track its
    /// correctness: among opinions of 2.0 nats or more on real speech it was right
    /// 2 times out of 4, and the two largest margins in the set were both wrong.
    ///
    /// The scorer itself is sound: over the same windows it rates "banana" and
    /// "elephant" about ten nats below either real candidate. The pair is simply
    /// one CTC token apart ("g" against "ck") in a single frame, which is where a
    /// 110M CTC head has least to say. Enabling it would replace a decision that is
    /// already right nine times out of ten with a coin flip.
    func testShippingTableIsEmptyBecauseTheMeasurementDidNotSupportLogLock() {
        XCTAssertTrue(
            SoundAlikeGroups.all.isEmpty,
            """
            Sound-alike rescoring is disabled on purpose. Adding a group here turns \
            it on for real dictation, so re-measure the pair first: the log/lock \
            experiment showed the CTC head choosing correctly barely half the time.
            """
        )
    }

    /// With the shipping table, the layer is inert on any transcript.
    func testShippingTableChangesNothing() {
        let live = SoundAlikeRescorer(
            config: .init(minimumWinMargin: 1.0),
            tokenize: { [self] in tokens($0) }
        )
        let words = [
            TimedWord(text: "the", startTime: 0, endTime: 1),
            TimedWord(text: "cat", startTime: 1, endTime: 4),
        ]
        let result = live.rescore(
            text: "the cat", words: words, logProbs: audio(saying: 2), frameDuration: 1, blankId: blank
        )
        XCTAssertEqual(result.text, "the cat")
        XCTAssertFalse(result.wasModified)
    }
}
