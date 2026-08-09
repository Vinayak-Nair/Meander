import XCTest
@testable import MeanderKit

final class SpokenTimeTests: XCTestCase {
    func testSpellsOutHoursAsDigits() {
        XCTAssertEqual(SpokenTime.format("three pm works for me"), "3pm works for me")
        XCTAssertEqual(SpokenTime.format("eight am"), "8am")
        XCTAssertEqual(SpokenTime.format("twelve pm"), "12pm")
    }

    func testNormalizesMeridiemSpelling() {
        XCTAssertEqual(SpokenTime.format("3 p.m. works"), "3pm works")
        XCTAssertEqual(SpokenTime.format("3 pm works"), "3pm works")
        XCTAssertEqual(SpokenTime.format("11:45 am tomorrow"), "11:45am tomorrow")
    }

    func testHandlesMinutes() {
        XCTAssertEqual(SpokenTime.format("three thirty pm"), "3:30pm")
        XCTAssertEqual(SpokenTime.format("three fifteen pm"), "3:15pm")
        XCTAssertEqual(SpokenTime.format("three o'clock pm"), "3pm")
    }

    /// The reported failure: Parakeet returned "Tree pm works for me" for
    /// "3pm works for me". The meridiem is what makes this safe to repair.
    func testRepairsMisheardHourBeforeMeridiem() {
        XCTAssertEqual(SpokenTime.format("Tree pm works for me."), "3pm works for me.")
        XCTAssertEqual(SpokenTime.format("free pm"), "3pm")
    }

    /// The same words anywhere else are left alone, which is the whole reason
    /// the repair is scoped to the meridiem position.
    func testLeavesTheSameWordsAloneOutsideATime() {
        for text in ["the tree fell down", "a tree in the garden", "free coffee today"] {
            XCTAssertEqual(SpokenTime.format(text), text)
        }
    }

    /// "to"/"for" are excluded from the hour map on purpose: unlike "tree" they
    /// read naturally in front of "PM", and rewriting correct text is worse than
    /// missing a repair.
    func testDoesNotRewriteOrdinaryPhrasesEndingInPM() {
        for text in ["I sent it to PM", "for PM approval", "PM me later", "spam works"] {
            XCTAssertEqual(SpokenTime.format(text), text)
        }
    }

    func testLeavesImpossibleClockTimesAlone() {
        XCTAssertEqual(SpokenTime.format("15 pm"), "15 pm")
        XCTAssertEqual(SpokenTime.format("0 am"), "0 am")
    }

    func testIsIdempotent() {
        XCTAssertEqual(SpokenTime.format("3pm already"), "3pm already")
        XCTAssertEqual(SpokenTime.format(SpokenTime.format("three pm")), "3pm")
    }

    /// End to end through the provider the user actually runs, since that is
    /// where ordering against capitalization matters.
    func testDeterministicCleanupFormatsTimes() async throws {
        let cleaned = try await DeterministicCleanup().clean("Tree pm works for me.", language: .english)
        XCTAssertEqual(cleaned, "3pm works for me.")
    }

    /// A sentence opening with a number has no letter to capitalize, and looking
    /// for one puts the capital inside the following word.
    func testSentenceStartingWithANumberIsNotCapitalizedMidWord() async throws {
        let cleanup = DeterministicCleanup()
        for (input, expected) in [
            ("3 apples are enough.", "3 apples are enough."),
            ("2 things happened. 5 people left.", "2 things happened. 5 people left."),
        ] {
            let cleaned = try await cleanup.clean(input, language: .english)
            XCTAssertEqual(cleaned, expected)
        }
    }
}
