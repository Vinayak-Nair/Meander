import XCTest
@testable import DriftKit

final class DeterministicCleanupTests: XCTestCase {
    let sut = DeterministicCleanup()

    func testRemovesEnglishFillers() async throws {
        let out = try await sut.clean("um so I uh went to the store", language: .english)
        XCTAssertEqual(out, "So I went to the store")
    }

    func testRemovesFillerPhrases() async throws {
        let out = try await sut.clean("this is, you know, pretty good", language: .english)
        XCTAssertFalse(out.lowercased().contains("you know"))
        XCTAssertTrue(out.contains("pretty good"))
    }

    func testCapitalizesSentences() async throws {
        let out = try await sut.clean("hello world. how are you?", language: .english)
        XCTAssertTrue(out.hasPrefix("Hello world."))
        XCTAssertTrue(out.contains("How are you?"))
    }

    func testCollapsesWhitespace() async throws {
        let out = try await sut.clean("hello    world", language: .english)
        XCTAssertEqual(out, "Hello world")
    }

    func testCapitalizesStandaloneI() async throws {
        let out = try await sut.clean("i think i can", language: .english)
        XCTAssertEqual(out, "I think I can")
    }

    func testRemovesSpaceBeforePunctuation() async throws {
        let out = try await sut.clean("wait , what ?", language: .english)
        XCTAssertEqual(out, "Wait, what?")
    }

    func testCollapsesDoubledWords() async throws {
        let out = try await sut.clean("I I went to the the store", language: .english)
        XCTAssertEqual(out, "I went to the store")
    }

    func testDoubledWordCollapseIsCaseInsensitiveKeepsFirstCasing() async throws {
        let out = try await sut.clean("The the cat sat", language: .english)
        XCTAssertEqual(out, "The cat sat")
    }

    func testDoubledWordCollapseLeavesPunctuatedRepeatsIntact() async throws {
        // "no, no" is deliberate, not a dictation stutter — the comma blocks it.
        let out = try await sut.clean("no, no that is fine", language: .english)
        XCTAssertTrue(out.lowercased().hasPrefix("no, no"))
    }

    // Indic scripts must never be word-stripped or altered beyond whitespace.
    func testMalayalamIsNonDestructive() async throws {
        let input = "എനിക്ക് വിശക്കുന്നു"
        let out = try await sut.clean(input, language: .malayalam)
        XCTAssertEqual(out, input)
    }

    func testAutoDetectsHindiAndPreserves() async throws {
        let input = "मुझे भूख लगी है"
        let out = try await sut.clean(input, language: .auto)
        XCTAssertEqual(out, input)
    }

    func testContainsIndicDetection() {
        XCTAssertTrue(DeterministicCleanup.containsIndic("तमिल"))
        XCTAssertTrue(DeterministicCleanup.containsIndic("mixed ಕನ್ನಡ text"))
        XCTAssertFalse(DeterministicCleanup.containsIndic("plain english"))
    }
}
