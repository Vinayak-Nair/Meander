import XCTest
@testable import MeanderKit

/// Integrity checks for the enhancement-contract system prompt. The eval cases
/// and the model-driven runner live in the `MeanderEval` executable target (run
/// `swift run meander-eval`), which produces the human-readable quality report.
final class EnhancementContractTests: XCTestCase {
    func testSystemPromptCoversBothHalvesOfTheContract() {
        let prompt = EnhancementContract.systemPrompt
        XCTAssertTrue(prompt.contains("DO:"))
        XCTAssertTrue(prompt.contains("DO NOT:"))
        // A few load-bearing guarantees must be spelled out verbatim.
        XCTAssertTrue(prompt.contains("Output ONLY the cleaned text"))
        XCTAssertTrue(prompt.lowercased().contains("false start"))
        XCTAssertTrue(prompt.lowercased().contains("profanity"))
    }
}
