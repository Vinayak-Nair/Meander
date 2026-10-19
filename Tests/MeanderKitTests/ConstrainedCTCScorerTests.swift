@testable import MeanderKit
import XCTest

/// The acoustic scorer is pure arithmetic over a log-probability matrix, so these
/// tests hand it matrices with a known answer instead of a model. That is what
/// makes "the audio supports this spelling" a checkable claim rather than a hope.
final class ConstrainedCTCScorerTests: XCTestCase {
    /// Vocabulary of three symbols: 0 and 1 are tokens, 2 is blank.
    private let blank = 2

    /// A frame that is almost certain about one symbol.
    private func frame(certain symbol: Int) -> [Float] {
        (0..<3).map { $0 == symbol ? -0.01 : -6.0 }
    }

    private func score(_ tokens: [Int], _ frames: [[Float]]) -> Double? {
        ConstrainedCTCScorer.logLikelihood(
            tokens: tokens, logProbs: frames, blankId: blank, startFrame: 0, endFrame: frames.count
        )
    }

    /// Audio that clearly says token 0 then token 1 must score the matching
    /// sequence far above the reversed one.
    func testPrefersTheSequenceTheFramesActuallySupport() throws {
        let frames = [frame(certain: 0), frame(certain: 1), frame(certain: blank)]
        let matching = try XCTUnwrap(score([0, 1], frames))
        let reversed = try XCTUnwrap(score([1, 0], frames))
        XCTAssertGreaterThan(matching, reversed + 5)
        // Near-certain frames leave almost no probability mass unexplained.
        XCTAssertGreaterThan(matching, -0.5)
    }

    /// The two candidates in a sound-alike comparison are scored over identical
    /// frames, so their difference is a like-for-like likelihood ratio.
    func testScoresAreComparableAcrossCandidatesOverTheSameWindow() throws {
        let frames = [frame(certain: blank), frame(certain: 0), frame(certain: blank)]
        let present = try XCTUnwrap(score([0], frames))
        let absent = try XCTUnwrap(score([1], frames))
        XCTAssertGreaterThan(present - absent, 5)
    }

    /// A window shorter than the token sequence cannot hold it, and "no opinion"
    /// must not be reported as "unlikely" - a nil keeps the word unchanged, a
    /// large negative number would invite a replacement.
    func testWindowTooShortForTheSequenceYieldsNoOpinion() {
        let frames = [frame(certain: 0)]
        XCTAssertNil(score([0, 1], frames))
    }

    /// CTC needs an emitted blank between two identical tokens, so three frames
    /// are the minimum for a repeated pair and two are not enough.
    func testRepeatedTokensNeedABlankBetweenThem() {
        let frames = [frame(certain: 0), frame(certain: 0)]
        XCTAssertNil(score([0, 0], frames))
        XCTAssertNotNil(score([0, 0], frames + [frame(certain: 0)]))
    }

    func testRejectsTokensOutsideTheVocabulary() {
        let frames = [frame(certain: 0), frame(certain: 1)]
        XCTAssertNil(score([0, 99], frames))
        XCTAssertNil(
            ConstrainedCTCScorer.logLikelihood(
                tokens: [0], logProbs: frames, blankId: 99, startFrame: 0, endFrame: 2
            )
        )
    }

    func testEmptyWindowOrEmptyCandidateYieldsNoOpinion() {
        let frames = [frame(certain: 0), frame(certain: 1)]
        XCTAssertNil(
            ConstrainedCTCScorer.logLikelihood(
                tokens: [0], logProbs: frames, blankId: blank, startFrame: 1, endFrame: 1
            )
        )
        XCTAssertNil(score([], frames))
    }

    /// Summing over alignments, not just the best one, is what makes the score a
    /// likelihood: a token that could sit in either of two frames must score
    /// higher than the single best placement alone.
    func testSumsOverAlignmentsRatherThanTakingTheBestPath() throws {
        let ambiguous: [[Float]] = [
            [log(0.5), log(0.25), log(0.25)],
            [log(0.5), log(0.25), log(0.25)],
        ]
        let total = try XCTUnwrap(score([0], ambiguous))
        // Best single path: token in frame 0 then blank, or blank then token.
        let bestSinglePath = log(0.5) + log(0.25)
        XCTAssertGreaterThan(total, bestSinglePath)
    }
}
