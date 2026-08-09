import XCTest
@testable import MeanderKit

final class CommandProcessorTests: XCTestCase {
    private let proc = CommandProcessor()

    func testNewLine() {
        XCTAssertEqual(proc.process("hello new line world"), "hello\nworld")
    }

    func testNewParagraph() {
        XCTAssertEqual(proc.process("one new paragraph two"), "one\n\ntwo")
    }

    func testComma() {
        XCTAssertEqual(proc.process("apples comma oranges"), "apples, oranges")
    }

    func testPeriodAndFullStop() {
        XCTAssertEqual(proc.process("done period next full stop"), "done. next.")
    }

    func testQuestionMark() {
        XCTAssertEqual(proc.process("really question mark"), "really?")
    }

    func testExclamation() {
        XCTAssertEqual(proc.process("wow exclamation point"), "wow!")
    }

    func testColonSemicolon() {
        XCTAssertEqual(proc.process("items colon one semicolon two"), "items: one; two")
    }

    func testParentheses() {
        XCTAssertEqual(proc.process("note open paren important close paren done"), "note (important) done")
    }

    func testScratchThatRemovesCurrentSentence() {
        XCTAssertEqual(proc.process("Hello there. This is wrong scratch that"), "Hello there.")
    }

    func testScratchThatClearsWhenNoBoundary() {
        XCTAssertEqual(proc.process("this is wrong scratch that"), "")
    }

    func testBulletList() {
        XCTAssertEqual(proc.process("new bullet milk new bullet eggs"), "- milk\n- eggs")
    }

    func testNormalizesAttachedPunctuation() {
        // The transcriber may glue punctuation on: "comma," must still match.
        XCTAssertEqual(proc.process("a comma, b"), "a, b")
    }

    func testNonCommandWordsPassThrough() {
        XCTAssertEqual(proc.process("the quick brown fox"), "the quick brown fox")
    }

    func testPartialCommandKeepsWord() {
        // "new" followed by a non-command word stays literal.
        XCTAssertEqual(proc.process("a new car"), "a new car")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(proc.process(""), "")
    }
}
