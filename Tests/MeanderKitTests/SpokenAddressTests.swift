import XCTest
@testable import MeanderKit

final class SpokenAddressTests: XCTestCase {
    func testAssemblesEmailAddress() {
        XCTAssertEqual(SpokenAddress.format("vinayak at gmail dot com"), "vinayak@gmail.com")
        XCTAssertEqual(SpokenAddress.format("hello at meander dot io"), "hello@meander.io")
    }

    /// A domain spelled aloud arrives as separate words; the whole run between
    /// "at" and "dot" is one host.
    func testGluesMultiWordDomain() {
        XCTAssertEqual(
            SpokenAddress.format("Vinayak at vinayak v nair dot com"),
            "Vinayak@vinayakvnair.com"
        )
    }

    func testGluesMultiWordLocalPart() {
        XCTAssertEqual(
            SpokenAddress.format("vinayak nair at gmail dot com"),
            "vinayaknair@gmail.com"
        )
    }

    /// The sentence introducing an address must not be pulled into the local
    /// part. Ordinary English words are where it stops.
    func testDoesNotSwallowTheIntroducingSentence() {
        XCTAssertEqual(
            SpokenAddress.format("this is Vinayak at gmail dot com"),
            "this is Vinayak@gmail.com"
        )
    }

    /// With no name-like word before it, "at" is just a preposition and only the
    /// host gets assembled.
    func testKeepsAtAsAWordWhenThereIsNoLocalPart() {
        XCTAssertEqual(SpokenAddress.format("email me at meander dot com"), "email me at meander.com")
    }

    func testAssemblesBareDomain() {
        XCTAssertEqual(SpokenAddress.format("go to vinayakvnair dot com"), "go to vinayakvnair.com")
    }

    func testKeepsSentencePunctuation() {
        XCTAssertEqual(
            SpokenAddress.format("write to vinayak at gmail dot com."),
            "write to vinayak@gmail.com."
        )
    }

    /// "at" is one of the commonest words in English, so everything here hinges
    /// on the "dot <tld>" ending. Without it nothing may change.
    func testLeavesOrdinarySentencesAlone() {
        for text in [
            "let's meet at the office",
            "I looked at the dot on the screen",
            "he is at home",
            "connect the dot to the line",
            "meet me at three",
        ] {
            XCTAssertEqual(SpokenAddress.format(text), text)
        }
    }

    /// An unrelated "at" earlier in the sentence must not reach across ordinary
    /// words to a later domain.
    func testAtDoesNotReachAcrossProse() {
        XCTAssertEqual(
            SpokenAddress.format("I looked at the site called meander dot com"),
            "I looked at the site called meander.com"
        )
    }

    func testEndToEndThroughDeterministicCleanup() async throws {
        let cleaned = try await DeterministicCleanup()
            .clean("Vinayak at vinayak v nair dot com", language: .english)
        XCTAssertEqual(cleaned, "Vinayak@vinayakvnair.com")
    }

    /// The bug behind the garbled address: a filler between two copies of a word
    /// hid the repetition from the doubled-word collapse.
    func testFillerBetweenDuplicatesStillCollapses() async throws {
        let cleanup = DeterministicCleanup()
        for (input, expected) in [
            ("Vinayak um Vinayak dot com", "vinayak.com"),
            ("the um the cat sat", "The cat sat"),
        ] {
            let cleaned = try await cleanup.clean(input, language: .english)
            XCTAssertEqual(cleaned, expected)
        }
    }
}
